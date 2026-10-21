#import <AVFoundation/AVFoundation.h>
#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include <glad/glad.h>
#include <GLFW/glfw3.h>

#include <algorithm>
#include <cstring>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

struct AudioTrack {
    AVAudioEngine *engine = nil;
    AVAudioPlayerNode *player = nil;
    AVAudioUnitTimePitch *timePitch = nil;
    AVAudioPCMBuffer *buffer = nil;
    AVAudioPCMBuffer *playBuffer = nil;
    std::vector<float> waveform;
    double duration = 0;
    double selectionStart = 0.0;
    double selectionEnd = 1.0;
    float pitchCents = 0.0f;
    float speed = 1.0f;
    bool reversed = false;
    bool playing = false;
};

static AudioTrack track;
static GLuint audioTexture = 0;
static GLint durationUniform = -1;
static GLint timeUniform = -1;
static GLint playingUniform = -1;
static GLint loadedUniform = -1;
static GLint selectionUniform = -1;
static bool selecting = false;
static double dragStart = 0.0;
static std::string currentName = "Drop an audio file here or press O to open";

static void scheduleSelection() {
    if (!track.player || !track.buffer) return;
    [track.player stop];
    const AVAudioFrameCount total = track.buffer.frameLength;
    AVAudioFramePosition first = static_cast<AVAudioFramePosition>(track.selectionStart * total);
    AVAudioFramePosition last = static_cast<AVAudioFramePosition>(track.selectionEnd * total);
    first = std::clamp<AVAudioFramePosition>(first, 0, total - 1);
    last = std::clamp<AVAudioFramePosition>(last, first + 1, total);
    const AVAudioFrameCount count = static_cast<AVAudioFrameCount>(last - first);
    AVAudioPCMBuffer *segment = [[AVAudioPCMBuffer alloc] initWithPCMFormat:track.buffer.format frameCapacity:count];
    segment.frameLength = count;
    float * const *source = track.buffer.floatChannelData;
    float * const *destination = segment.floatChannelData;
    for (AVAudioChannelCount ch = 0; ch < track.buffer.format.channelCount; ++ch) {
        for (AVAudioFrameCount i = 0; i < count; ++i) {
            const AVAudioFrameCount sourceIndex = track.reversed ? static_cast<AVAudioFrameCount>(last - 1 - i) : static_cast<AVAudioFrameCount>(first + i);
            destination[ch][i] = source[ch][sourceIndex];
        }
    }
    track.playBuffer = segment;
    [track.player scheduleBuffer:segment atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
    track.timePitch.rate = track.speed;
    track.timePitch.pitch = track.pitchCents;
}

static void stopAudio() {
    if (track.player) [track.player stop];
    if (track.engine) [track.engine stop];
    track.playing = false;
}

static bool loadAudio(const std::string &path) {
    @autoreleasepool {
        NSError *error = nil;
        NSURL *url = [NSURL fileURLWithPath:[NSString stringWithUTF8String:path.c_str()]];
        AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
        if (!file) {
            std::cerr << "Could not open audio file: " << (error.localizedDescription.UTF8String ?: "unknown error") << '\n';
            return false;
        }
        AVAudioFormat *format = file.processingFormat;
        const AVAudioFrameCount frames = static_cast<AVAudioFrameCount>(file.length);
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:frames];
        if (!buffer || ![file readIntoBuffer:buffer error:&error]) {
            std::cerr << "Could not decode audio file: " << (error.localizedDescription.UTF8String ?: "unknown error") << '\n';
            return false;
        }
        stopAudio();
        track.buffer = buffer;
        track.duration = static_cast<double>(buffer.frameLength) / format.sampleRate;
        track.selectionStart = 0.0; track.selectionEnd = 1.0; track.reversed = false;
        track.pitchCents = 0.0f; track.speed = 1.0f;
        track.waveform.clear();
        float * const *channels = buffer.floatChannelData;
        const AVAudioChannelCount channelCount = format.channelCount;
        if (!channels || buffer.frameLength == 0) {
            std::cerr << "The file did not decode to floating point audio.\n";
            return false;
        }
        constexpr size_t textureSamples = 16384;
        track.waveform.resize(textureSamples);
        for (size_t i = 0; i < textureSamples; ++i) {
            const uint64_t start = (static_cast<uint64_t>(i) * buffer.frameLength) / textureSamples;
            const uint64_t end = std::max<uint64_t>(start + 1, (static_cast<uint64_t>(i + 1) * buffer.frameLength) / textureSamples);
            float peak = 0.0f;
            for (uint64_t frame = start; frame < std::min<uint64_t>(end, buffer.frameLength); ++frame) {
                float sample = 0.0f;
                for (AVAudioChannelCount ch = 0; ch < channelCount; ++ch) sample += channels[ch][frame];
                sample /= static_cast<float>(channelCount);
                peak = std::max(peak, std::abs(sample));
            }
            track.waveform[i] = peak;
        }
        track.engine = [[AVAudioEngine alloc] init];
        track.player = [[AVAudioPlayerNode alloc] init];
        track.timePitch = [[AVAudioUnitTimePitch alloc] init];
        [track.engine attachNode:track.player];
        [track.engine attachNode:track.timePitch];
        [track.engine connect:track.player to:track.timePitch format:format];
        [track.engine connect:track.timePitch to:track.engine.mainMixerNode format:format];
        if (![track.engine startAndReturnError:&error]) {
            std::cerr << "Could not start audio output: " << (error.localizedDescription.UTF8String ?: "unknown error") << '\n';
            return false;
        }
        scheduleSelection();
        track.playing = false;
        currentName = url.lastPathComponent.UTF8String ?: path;
        glBindTexture(GL_TEXTURE_1D, audioTexture);
        glTexImage1D(GL_TEXTURE_1D, 0, GL_R32F, static_cast<GLsizei>(track.waveform.size()), 0, GL_RED, GL_FLOAT, track.waveform.data());
        return true;
    }
}

static void openPicker(GLFWwindow *window) {
    @autoreleasepool {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [NSApp activateIgnoringOtherApps:YES];
        panel.canChooseFiles = YES;
        panel.canChooseDirectories = NO;
        panel.allowsMultipleSelection = NO;
        panel.allowedContentTypes = @[[UTType typeWithFilenameExtension:@"wav"], [UTType typeWithFilenameExtension:@"mp4"], [UTType typeWithFilenameExtension:@"m4a"], [UTType typeWithFilenameExtension:@"aiff"], [UTType typeWithFilenameExtension:@"mp3"]];
        if ([panel runModal] == NSModalResponseOK) {
            const char *path = panel.URL.fileSystemRepresentation;
            if (path) loadAudio(path);
        }
        glfwFocusWindow(window);
    }
}

static GLuint makeShader(GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);
    GLint ok = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[2048]; glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
        std::cerr << "Shader compile error: " << log << '\n';
        glDeleteShader(shader); return 0;
    }
    return shader;
}

static GLuint makeProgram() {
    const char *vertex = R"GLSL(#version 330 core
    out vec2 uv;
    void main() {
        vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
        uv = p;
        gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
    })GLSL";
    const char *fragment = R"GLSL(#version 330 core
    in vec2 uv;
    out vec4 color;
    uniform sampler1D audioData;
    uniform float elapsed;
    uniform float duration;
    uniform float isPlaying;
    uniform float isLoaded;
    uniform vec2 selection;
    float audioAt(float x) { return texture(audioData, clamp(x, 0.001, 0.999)).r; }
    void main() {
        vec2 p = uv;
        vec2 q = (p - 0.5) * vec2(1.0, 1.75);
        vec3 col = vec3(0.018, 0.023, 0.055);
        float grid = max(abs(fract(p.x * 16.0) - 0.5), abs(fract(p.y * 8.0) - 0.5));
        col += vec3(0.025, 0.035, 0.075) * smoothstep(0.47, 0.5, grid);
        float x = p.x;
        float a = audioAt(x) * isLoaded;
        float inside = step(selection.x, x) * step(x, selection.y);
        col *= mix(0.20, 1.0, inside);
        float edge = max(exp(-abs(x-selection.x)*350.0), exp(-abs(x-selection.y)*350.0));
        col += vec3(0.18, 0.9, 0.8) * edge * isLoaded * 0.7;
        float phase = elapsed * (0.8 + isPlaying * 0.7);
        float center = 0.0;
        float wave1 = sin(x * 18.0 - phase) * 0.12 + (a * 0.72 + 0.015) * sin(x * 35.0 - phase * 0.7);
        float wave2 = sin(x * 12.0 + phase * 0.75) * 0.10 + (a * 0.52 + 0.012) * cos(x * 27.0 + phase);
        float wave3 = sin(x * 25.0 - phase * 0.5) * 0.07 + (a * 0.38 + 0.01) * sin(x * 48.0 + phase * 0.6);
        float d1 = abs(q.y - center - wave1);
        float d2 = abs(q.y - center - wave2 - 0.23);
        float d3 = abs(q.y - center - wave3 + 0.23);
        col += vec3(0.13, 0.82, 1.0) * exp(-d1 * 90.0) * (0.45 + a * 2.0);
        col += vec3(0.94, 0.22, 0.72) * exp(-d2 * 75.0) * (0.40 + a * 1.5);
        col += vec3(0.55, 0.36, 1.0) * exp(-d3 * 80.0) * (0.35 + a * 1.2);
        float waveform = abs(q.y) - (a * 0.50 + 0.004);
        col += vec3(0.12, 0.30, 0.48) * exp(-abs(waveform) * 130.0) * 0.65;
        float playhead = duration > 0.0 ? fract(elapsed / duration) : 0.0;
        float cursor = exp(-abs(x - playhead) * 450.0) * isLoaded;
        col += vec3(0.9, 0.95, 1.0) * cursor * 0.7;
        float vignette = 1.0 - 0.45 * dot((p - 0.5) * 1.2, (p - 0.5) * 1.2);
        color = vec4(col * vignette, 1.0);
    })GLSL";
    GLuint vs = makeShader(GL_VERTEX_SHADER, vertex), fs = makeShader(GL_FRAGMENT_SHADER, fragment);
    if (!vs || !fs) return 0;
    GLuint program = glCreateProgram(); glAttachShader(program, vs); glAttachShader(program, fs); glLinkProgram(program);
    glDeleteShader(vs); glDeleteShader(fs);
    GLint ok = GL_FALSE; glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (!ok) { char log[2048]; glGetProgramInfoLog(program, sizeof(log), nullptr, log); std::cerr << "Shader link error: " << log << '\n'; glDeleteProgram(program); return 0; }
    return program;
}

static void keyCallback(GLFWwindow *window, int key, int, int action, int) {
    if (action != GLFW_PRESS) return;
    if (key == GLFW_KEY_ESCAPE) glfwSetWindowShouldClose(window, GLFW_TRUE);
    if (key == GLFW_KEY_O) openPicker(window);
    if (key == GLFW_KEY_SPACE && track.player) {
        if (track.playing) { [track.player pause]; track.playing = false; }
        else { [track.player play]; track.playing = true; }
    }
    if (key == GLFW_KEY_R && track.player) { track.reversed = !track.reversed; scheduleSelection(); [track.player play]; track.playing = true; }
    if (key == GLFW_KEY_LEFT && track.timePitch) { track.pitchCents = std::max(-1200.0f, track.pitchCents - 100.0f); track.timePitch.pitch = track.pitchCents; }
    if (key == GLFW_KEY_RIGHT && track.timePitch) { track.pitchCents = std::min(1200.0f, track.pitchCents + 100.0f); track.timePitch.pitch = track.pitchCents; }
    if (key == GLFW_KEY_DOWN && track.timePitch) { track.speed = std::max(0.5f, track.speed - 0.05f); track.timePitch.rate = track.speed; }
    if (key == GLFW_KEY_UP && track.timePitch) { track.speed = std::min(2.0f, track.speed + 0.05f); track.timePitch.rate = track.speed; }
    if (key == GLFW_KEY_C && track.player) { track.selectionStart = 0.0; track.selectionEnd = 1.0; scheduleSelection(); }
}

static void mouseButtonCallback(GLFWwindow *window, int button, int action, int) {
    if (button != GLFW_MOUSE_BUTTON_LEFT || track.waveform.empty()) return;
    if (action == GLFW_PRESS) {
        double x, y; int width, height; glfwGetCursorPos(window, &x, &y); glfwGetWindowSize(window, &width, &height);
        selecting = true; dragStart = std::clamp(x / width, 0.0, 1.0);
        track.selectionStart = dragStart; track.selectionEnd = dragStart;
    } else if (action == GLFW_RELEASE && selecting) {
        double x, y; int width, height; glfwGetCursorPos(window, &x, &y); glfwGetWindowSize(window, &width, &height);
        double finish = std::clamp(x / width, 0.0, 1.0);
        track.selectionStart = std::min(dragStart, finish); track.selectionEnd = std::max(dragStart, finish);
        if (track.selectionEnd - track.selectionStart < 0.005) { track.selectionStart = 0.0; track.selectionEnd = 1.0; }
        selecting = false; scheduleSelection();
    }
}

static void cursorCallback(GLFWwindow *window, double x, double) {
    if (!selecting) return;
    int width, height; glfwGetWindowSize(window, &width, &height);
    const double position = std::clamp(x / width, 0.0, 1.0);
    track.selectionStart = std::min(dragStart, position);
    track.selectionEnd = std::max(dragStart, position);
}

static void dropCallback(GLFWwindow *, int count, const char **paths) {
    if (count > 0 && paths[0]) loadAudio(paths[0]);
}

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        if (!glfwInit()) { std::cerr << "Could not initialize GLFW.\n"; return 1; }
        glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
        glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
        glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
        glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GL_TRUE);
        GLFWwindow *window = glfwCreateWindow(1100, 680, "Live Audio Deck | drag to crop", nullptr, nullptr);
        if (!window) { std::cerr << "Could not create OpenGL window.\n"; glfwTerminate(); return 1; }
        glfwMakeContextCurrent(window); glfwSwapInterval(1);
        glfwSetKeyCallback(window, keyCallback); glfwSetDropCallback(window, dropCallback); glfwSetMouseButtonCallback(window, mouseButtonCallback); glfwSetCursorPosCallback(window, cursorCallback);
        if (!gladLoadGLLoader((GLADloadproc)glfwGetProcAddress)) { std::cerr << "Could not load OpenGL.\n"; return 1; }
        GLuint program = makeProgram();
        if (!program) return 1;
        GLuint vao; glGenVertexArrays(1, &vao); glBindVertexArray(vao);
        glGenTextures(1, &audioTexture); glBindTexture(GL_TEXTURE_1D, audioTexture);
        std::vector<float> silence(16384, 0.0f);
        glTexImage1D(GL_TEXTURE_1D, 0, GL_R32F, static_cast<GLsizei>(silence.size()), 0, GL_RED, GL_FLOAT, silence.data());
        glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MIN_FILTER, GL_LINEAR); glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glUseProgram(program);
        glUniform1i(glGetUniformLocation(program, "audioData"), 0);
        durationUniform = glGetUniformLocation(program, "duration"); timeUniform = glGetUniformLocation(program, "elapsed");
        playingUniform = glGetUniformLocation(program, "isPlaying"); loadedUniform = glGetUniformLocation(program, "isLoaded");
        selectionUniform = glGetUniformLocation(program, "selection");
        while (!glfwWindowShouldClose(window)) {
            int width, height; glfwGetFramebufferSize(window, &width, &height);
            glViewport(0, 0, width, height); glClear(GL_COLOR_BUFFER_BIT);
            glUseProgram(program); glActiveTexture(GL_TEXTURE0); glBindTexture(GL_TEXTURE_1D, audioTexture);
            glUniform1f(timeUniform, static_cast<float>(glfwGetTime())); glUniform1f(durationUniform, static_cast<float>(track.duration));
            glUniform1f(playingUniform, track.playing ? 1.0f : 0.0f); glUniform1f(loadedUniform, track.waveform.empty() ? 0.0f : 1.0f);
            glUniform2f(selectionUniform, static_cast<float>(track.selectionStart), static_cast<float>(track.selectionEnd));
            glDrawArrays(GL_TRIANGLES, 0, 3);
            std::string title = "Live Audio Deck | " + currentName + (track.playing ? " • PLAYING" : " • PAUSED") + " | pitch " + std::to_string(static_cast<int>(track.pitchCents / 100)) + " st | speed " + std::to_string(track.speed) + "x | " + (track.reversed ? "REVERSE" : "FORWARD") + " | O open • drag crop • Space play • ←/→ pitch • ↑/↓ speed • R reverse • C reset";
            glfwSetWindowTitle(window, title.c_str());
            glfwSwapBuffers(window); glfwPollEvents();
        }
        stopAudio();
        glDeleteTextures(1, &audioTexture); glDeleteVertexArrays(1, &vao); glDeleteProgram(program);
        glfwDestroyWindow(window); glfwTerminate();
    }
    return 0;
}
