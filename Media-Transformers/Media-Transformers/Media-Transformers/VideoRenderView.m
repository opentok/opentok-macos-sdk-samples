//
//  VideoRenderView.m
//  Media-Transformers
//
//  Created by Jerónimo Valli on 11/17/22.
//  Copyright (c) 2022 Vonage. All rights reserved.
//

#import "VideoRenderView.h"
#import <opentok/opentok.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/glu.h>
#import <AVFoundation/AVFoundation.h>

#import <mach/mach_time.h>
#define SKWTimestamp() (((double)mach_absolute_time()) * 1.0e-09)

#define RTC_STRINGIZE(...) #__VA_ARGS__

// Vertex shader doesn't do anything except pass coordinates through.
static const char kVertexShaderSource[] =
RTC_STRINGIZE(
              attribute vec2 position;
              attribute vec2 texcoord;
              varying vec2 v_texcoord;
              void main() {
                  gl_Position = vec4(position.x, position.y, 0.0, 1.0);
                  v_texcoord = texcoord;
              }
              );

// Fragment shader converts YUV values from input textures into a final RGB
// pixel. The conversion formula is from http://www.fourcc.org/fccyvrgb.php.
static const char kFragmentShaderSource[] =
RTC_STRINGIZE(
            varying vec2 v_texcoord;
            uniform sampler2D s_textureY;
            uniform sampler2D s_textureU;
            uniform sampler2D s_textureV;
            void main() {
                float y, u, v, r, g, b;
                y = texture2D(s_textureY, v_texcoord).r;
                u = texture2D(s_textureU, v_texcoord).r;
                v = texture2D(s_textureV, v_texcoord).r;
                y = 1.1643 * (y - 0.0625);
                u = u - 0.5;
                v = v - 0.5;
                
                r = y + 1.5958 * v;
                g = y - 0.39173 * u - 0.81290 * v;
                b = y + 2.017 * u;
                gl_FragColor = vec4(r, g, b, 1.0);
            }
);

// Compiles a shader of the given |type| with GLSL source |source| and returns
// the shader handle or 0 on error.
static GLuint CreateShader(GLenum type, const GLchar* source) {
    GLuint shader = glCreateShader(type);
    if (!shader) {
        return 0;
    }
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    GLint compileStatus = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &compileStatus);
    if (compileStatus == GL_FALSE) {
        glDeleteShader(shader);
        shader = 0;
    }
    return shader;
}

// Links a shader program with the given vertex and fragment shaders and
// returns the program handle or 0 on error.
static GLuint CreateProgram(GLuint vertexShader, GLuint fragmentShader) {
    if (vertexShader == 0 || fragmentShader == 0) {
        return 0;
    }
    GLuint program = glCreateProgram();
    if (!program) {
        return 0;
    }
    glAttachShader(program, vertexShader);
    glAttachShader(program, fragmentShader);
    glLinkProgram(program);
    GLint linkStatus = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &linkStatus);
    if (linkStatus == GL_FALSE) {
        glDeleteProgram(program);
        program = 0;
    }
    return program;
}

static const GLsizei kNumTextureSets = 2;
static const GLsizei kNumTextures = 3 * kNumTextureSets;

@implementation VideoRenderView {
    otc_video_frame * _videoFrame;
    NSLock* _frameLock;
    BOOL _renderingEnabled;
    
    BOOL _isInitialized;
    NSUInteger _currentTextureSet;
    // Handles for OpenGL constructs.
    GLuint _textures[kNumTextures];
    GLuint _program;
    GLint _position;
    GLint _texcoord;
    GLint _ySampler;
    GLint _uSampler;
    GLint _vSampler;

    size_t _lastDrawnWidth;
    size_t _lastDrawnHeight;
    BOOL _mirroring;
    GLfloat _vertices[16];
    
    AVAssetWriter *videoWriter;
    AVAssetWriterInput* writerInput;
    int frameCount;
    BOOL recording;
    
    NSString *filePath;
}

- (void) awakeFromNib
{
    _frameLock = [[NSLock alloc] init];
    _renderingEnabled = YES;
    _videoFrame = NULL;
    frameCount = 1;

    NSOpenGLPixelFormatAttribute attrs[] =
    {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFANoRecovery,
        NSOpenGLPFADepthSize, 0,
        // Must specify the 3.2 Core Profile to use OpenGL 3.2
        NSOpenGLPFAOpenGLProfile,
        NSOpenGLProfileVersionLegacy,
        0
    };
    
    NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    
    if (!pf)
    {
        NSLog(@"No OpenGL pixel format");
    }
    
    NSOpenGLContext* context = [[NSOpenGLContext alloc] initWithFormat:pf shareContext:nil];
    
    [self setPixelFormat:pf];
    
    [self setOpenGLContext:context];
    
    NSTimer *updateTimer = [NSTimer timerWithTimeInterval:1.0f/30.0f target:self selector:@selector(idle:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:updateTimer forMode:NSDefaultRunLoopMode];
}

- (void)idle:(NSTimer*)timer
{
    [self setNeedsDisplay:YES];
}

- (void)prepareOpenGL {
    [super prepareOpenGL];
    [self setupGL];
}

- (void)clearGLContext {
    [self teardownGL];
    [super clearGLContext];
}

- (void)reshape {
    [[self openGLContext] makeCurrentContext];
    NSRect viewport = self.frame;
    glViewport(0, 0, viewport.size.width, viewport.size.height);
    [[self openGLContext] update];
    [super reshape];
}


-(void) startRecording {
    [_frameLock lock];

    NSNumber *number = [[NSUserDefaults standardUserDefaults] objectForKey:@"video_number"];
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:[number intValue]+1] forKey:@"video_number"];
    
    NSError *error = nil;
    
    NSArray * paths = NSSearchPathForDirectoriesInDomains (NSDesktopDirectory, NSUserDomainMask, YES);
    NSString * desktopPath = [paths objectAtIndex:0];
    filePath = [NSString stringWithFormat:@"%@/video%05d.mov", desktopPath, [number intValue]];
    
    videoWriter = [[AVAssetWriter alloc] initWithURL:
                                  [NSURL fileURLWithPath:filePath] fileType:AVFileTypeQuickTimeMovie
                                                              error:&error];
    
    int w = _lastDrawnWidth == 0 ? 640 : (int)_lastDrawnWidth;
    int h = _lastDrawnHeight == 0 ? 480 : (int)_lastDrawnHeight;
    
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                   AVVideoCodecH264, AVVideoCodecKey,
                                   AVVideoScalingModeResizeAspect, AVVideoScalingModeKey,
                                   [NSNumber numberWithInt:(int)w], AVVideoWidthKey,
                                   [NSNumber numberWithInt:(int)h], AVVideoHeightKey,
                                   nil];
    writerInput = [AVAssetWriterInput
                                        assetWriterInputWithMediaType:AVMediaTypeVideo
                                       outputSettings:videoSettings];
    
    [videoWriter addInput:writerInput];
    
    [videoWriter startWriting];

    frameCount = 0;
    [videoWriter startSessionAtSourceTime:CMTimeMake(frameCount, 30)];
    
    recording = YES;
    
    [_frameLock unlock];

}

- (BOOL) isRecording {
    BOOL ret;
    [_frameLock lock];
    ret = recording;
    [_frameLock unlock];
    return ret;
}

- (void) stopRecording {
    [_frameLock lock];
    if (recording) {
        recording = NO;
        [writerInput markAsFinished];
        [videoWriter finishWritingWithCompletionHandler:^{
            NSUserNotification *notification = [[NSUserNotification alloc] init];
            notification.title = @"Stream recording finalized!";
            notification.soundName = NSUserNotificationDefaultSoundName;
            [notification setValue:[NSImage imageNamed:@"icon.png"] forKey:@"_identityImage"];
            notification.userInfo = @{@"file":filePath};
            NSUserNotificationCenter * nc = [NSUserNotificationCenter defaultUserNotificationCenter];
            nc.delegate = self;
            [nc deliverNotification:notification];
            writerInput = nil;
            videoWriter = nil;
        }];
    }
    [_frameLock unlock];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification {
    NSString *file = [notification.userInfo objectForKey:@"file"];
    NSURL *fileURL = [NSURL fileURLWithPath:file];
    NSArray *fileURLs = [NSArray arrayWithObjects:fileURL, nil];
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:fileURLs];
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification {
    return YES;
}

- (void)dealloc {
    [self stopRecording];
}

void releasecallback( void *releaseRefCon, const void *baseAddress ) {
    otc_video_frame *frame = (otc_video_frame *)releaseRefCon;
    otc_video_frame_delete(frame);
}


- (void)drawRect:(NSRect)dirtyRect {
    [[self openGLContext] makeCurrentContext];
    glClear(GL_COLOR_BUFFER_BIT);

    [_frameLock lock];

    if (_videoFrame && _isInitialized) {
        
        if (recording) {
            
            CMSampleBufferRef sample;

            CVPixelBufferRef pixel_buffer = NULL;
            otc_video_frame *tmp = otc_video_frame_convert(OTC_VIDEO_FRAME_FORMAT_ARGB32, _videoFrame);
            
            CVPixelBufferCreateWithBytes(kCFAllocatorDefault, otc_video_frame_get_width(tmp), otc_video_frame_get_height(tmp), kCVPixelFormatType_32BGRA, (void*)otc_video_frame_get_plane_binary_data(tmp, 0), otc_video_frame_get_width(tmp) * 4, releasecallback, tmp, NULL, &pixel_buffer);
            CMVideoFormatDescriptionRef videoInfo = NULL;
            CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixel_buffer, &videoInfo);
            
            CMTime frameTime = CMTimeMake(frameCount, 30);
            CMSampleTimingInfo timing = {CMTimeMake(1, 30), frameTime, kCMTimeInvalid};
            
            CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixel_buffer, YES, NULL, NULL, videoInfo, &timing, &sample);

            CFRelease(videoInfo);
            CVPixelBufferRelease(pixel_buffer);
            
            [writerInput appendSampleBuffer:sample];

            CFRelease(sample);
        }

        glUseProgram(_program);
        
        NSRect viewport = self.frame;
        
        // Drawing code here.
        float imageRatio =
        (float)otc_video_frame_get_width(_videoFrame) / (float)otc_video_frame_get_height(_videoFrame);
        float viewportRatio =
        (float)viewport.size.width / (float)viewport.size.height;
        
        /*= {
         // X, Y, U, V.
         -1, -1, 0, 1,  // Bottom left.
         1,  -1, 1, 1,  // Bottom right.
         1,  1,  1, 0,  // Top right.
         -1, 1,  0, 0,  // Top left.
         };*/
        float scaleX = 1.0;
        float scaleY = 1.0;
        
        // Adjust position coordinates based on how the image will render to the
        // viewport. This logic tree implements a "scale to fill" semantic. You can
        // invert the logic if "scale to fit" works better for your needs.
        if (imageRatio > viewportRatio) {
            scaleY = viewportRatio / imageRatio;
        } else {
            scaleX = imageRatio / viewportRatio;
        }
        
        if (_mirroring) {
            scaleX *= -1;
        }
        
        _vertices[0] = -1 * scaleX;
        _vertices[1] = -1 * scaleY;
        _vertices[2] = 0;
        _vertices[3] = 1;
        _vertices[4] = 1 * scaleX;
        _vertices[5] = -1 * scaleY;
        _vertices[6] = 1;
        _vertices[7] = 1;
        _vertices[8] = 1 * scaleX;
        _vertices[9] = 1 * scaleY;
        _vertices[10] = 1;
        _vertices[11] = 0;
        _vertices[12] = -1 * scaleX;
        _vertices[13] = 1 * scaleY;
        _vertices[14] = 0;
        _vertices[15] = 0;
        
        if (![self updateTextureSizesForFrame:_videoFrame] ||
            ![self updateTextureDataForFrame:_videoFrame]) {
            return;
        }
        
        
        glVertexAttribPointer(_position, 2, GL_FLOAT, false,
                              4 * sizeof(GLfloat), _vertices);
        glEnableVertexAttribArray(_position);
        glVertexAttribPointer(_texcoord, 2, GL_FLOAT, false,
                              4 * sizeof(GLfloat), _vertices+2);
        glEnableVertexAttribArray(_texcoord);
        glDrawArrays(GL_TRIANGLE_FAN, 0, 4);

        _lastDrawnWidth = otc_video_frame_get_width(_videoFrame);
        _lastDrawnHeight = otc_video_frame_get_height(_videoFrame);
    }
    frameCount++;
    [_frameLock unlock];

    [[self openGLContext] flushBuffer];
}


- (BOOL)mirroring {
    return _mirroring;
}

- (void)setMirroring:(BOOL)mirroring {
    _mirroring = mirroring;
}

- (BOOL)clearFrame {
    if (!_isInitialized) {
        return NO;
    }
    [_frameLock lock];
    if(_videoFrame) {
        otc_video_frame_delete(_videoFrame);
        _videoFrame = NULL;
    }
    [_frameLock unlock];
    
    //[self performSelectorOnMainThread:@selector(setNeedsDisplay:) withObject:@YES waitUntilDone:NO];

    return YES;
}

- (BOOL)drawFrame:(otc_video_frame*)frame {
    if (_isInitialized) {
        [_frameLock lock];
        if(_videoFrame) {
            otc_video_frame_delete(_videoFrame);
            _videoFrame = NULL;
        }
        
        _videoFrame = otc_video_frame_copy(frame);
        
        [_frameLock unlock];
        
        //[self performSelectorOnMainThread:@selector(setNeedsDisplay:) withObject:@YES waitUntilDone:NO];
        return YES;
    }
    return NO;
}

- (void)setupGL {
    if (_isInitialized) {
        return;
    }
    
    if (![self setupProgram]) {
        return;
    }
    if (![self setupTextures]) {
        return;
    }

    NSRect viewport = self.frame;
    glViewport(0, 0, viewport.size.width, viewport.size.height);

    glUseProgram(_program);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glClearColor(0, 0, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    [[self openGLContext] flushBuffer];
    _isInitialized = YES;
}

- (void)teardownGL {
    if (!_isInitialized) {
        return;
    }
    glDeleteProgram(_program);
    _program = 0;
    glDeleteTextures(kNumTextures, _textures);
    _isInitialized = NO;
}

#pragma mark - Private

- (BOOL)setupProgram {
    NSAssert(!_program, @"program already set up");
    GLuint vertexShader = CreateShader(GL_VERTEX_SHADER, kVertexShaderSource);
    GLuint fragmentShader =
    CreateShader(GL_FRAGMENT_SHADER, kFragmentShaderSource);
    _program = CreateProgram(vertexShader, fragmentShader);
    // Shaders are created only to generate program.
    if (vertexShader) {
        glDeleteShader(vertexShader);
    }
    if (fragmentShader) {
        glDeleteShader(fragmentShader);
    }
    if (!_program) {
        return NO;
    }
    _position = glGetAttribLocation(_program, "position");
    _texcoord = glGetAttribLocation(_program, "texcoord");
    _ySampler = glGetUniformLocation(_program, "s_textureY");
    _uSampler = glGetUniformLocation(_program, "s_textureU");
    _vSampler = glGetUniformLocation(_program, "s_textureV");
    if (_position < 0 || _texcoord < 0 || _ySampler < 0 || _uSampler < 0 ||
        _vSampler < 0) {
        return NO;
    }
    return YES;
}

- (BOOL)setupTextures {
    glGenTextures(kNumTextures, _textures);
    // Set parameters for each of the textures we created.
    for (GLsizei i = 0; i < kNumTextures; i++) {
        glActiveTexture(GL_TEXTURE0 + i);
        glBindTexture(GL_TEXTURE_2D, _textures[i]);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
    return YES;
}

- (BOOL)updateTextureSizesForFrame:(otc_video_frame *)frame {
    if (otc_video_frame_get_height(frame) == _lastDrawnHeight &&
        otc_video_frame_get_width(frame) == _lastDrawnWidth) {
        return YES;
    }
    GLsizei lumaWidth = otc_video_frame_get_plane_width(frame, 0);
    GLsizei lumaHeight = otc_video_frame_get_plane_height(frame, 0);
    GLsizei chromaWidth = otc_video_frame_get_plane_width(frame, 1);
    GLsizei chromaHeight = otc_video_frame_get_plane_height(frame, 1);
    
    for (GLint i = 0; i < kNumTextureSets; i++) {
        glActiveTexture(GL_TEXTURE0 + i * 3);
        glBindTexture(GL_TEXTURE_2D, _textures[i * 3]);
        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_LUMINANCE,
                     lumaWidth,
                     lumaHeight,
                     0,
                     GL_LUMINANCE,
                     GL_UNSIGNED_BYTE,
                     0);
        
        glActiveTexture(GL_TEXTURE0 + i * 3 + 1);
        glBindTexture(GL_TEXTURE_2D, _textures[i * 3 + 1]);
        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_LUMINANCE,
                     chromaWidth,
                     chromaHeight,
                     0,
                     GL_LUMINANCE,
                     GL_UNSIGNED_BYTE,
                     0);
        
        glActiveTexture(GL_TEXTURE0 + i * 3 + 2);
        glBindTexture(GL_TEXTURE_2D, _textures[i * 3 + 2]);
        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_LUMINANCE,
                     chromaWidth,
                     chromaHeight,
                     0,
                     GL_LUMINANCE,
                     GL_UNSIGNED_BYTE,
                     0);
    }
    return YES;
}

- (BOOL)updateTextureDataForFrame:(otc_video_frame*)frame {
    GLint textureOffset = (GLint) _currentTextureSet * 3;
    NSAssert(textureOffset + 3 <= kNumTextures, @"invalid offset");
    
    glPixelStorei( GL_UNPACK_ALIGNMENT, 1);
    glPixelStorei( GL_PACK_ALIGNMENT, 1);
    
    GLsizei lumaWidth = otc_video_frame_get_plane_width(frame, 0);
    GLsizei lumaHeight = otc_video_frame_get_plane_height(frame, 0);
    GLsizei chromaWidth = otc_video_frame_get_plane_width(frame, 1);
    GLsizei chromaHeight = otc_video_frame_get_plane_height(frame, 1);
    
    glActiveTexture((GLenum)(GL_TEXTURE0 + textureOffset));
    // When setting texture sampler uniforms, the texture index is used not
    // the texture handle.
    glUniform1i(_ySampler, textureOffset);
    glBindTexture(GL_TEXTURE_2D, _textures[textureOffset]);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, lumaWidth, lumaHeight,
                    GL_LUMINANCE, GL_UNSIGNED_BYTE, otc_video_frame_get_plane_binary_data(frame, 0));
    glActiveTexture(GL_TEXTURE0 + textureOffset + 1);
    glUniform1i(_uSampler, textureOffset + 1);
    glBindTexture(GL_TEXTURE_2D, _textures[textureOffset +1]);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, chromaWidth, chromaHeight,
                    GL_LUMINANCE, GL_UNSIGNED_BYTE, otc_video_frame_get_plane_binary_data(frame, 1));
    glActiveTexture(GL_TEXTURE0 + textureOffset + 2);
    glUniform1i(_vSampler, textureOffset + 2);
    glBindTexture(GL_TEXTURE_2D, _textures[textureOffset + 2]);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, chromaWidth, chromaHeight,
                    GL_LUMINANCE, GL_UNSIGNED_BYTE, otc_video_frame_get_plane_binary_data(frame, 2));
    _currentTextureSet = (_currentTextureSet + 1) % kNumTextureSets;
    return YES;
}

@end

