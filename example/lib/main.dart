// ignore_for_file: avoid_print

import 'dart:math';
import 'package:example/audio_renderer.dart';

import 'package:flutter/material.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

List<int> notes = [60, 62, 64, 65, 67, 69, 71, 72];

void main() => runApp(const MeltyApp());

class MeltyApp extends StatefulWidget {
  const MeltyApp({Key? key}) : super(key: key);

  @override
  State<MeltyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MeltyApp> {
  AudioRenderer? _renderer;

  int sampleRate = 44100;
  int feedThreshold = 4000;
  int newBufferLength = 6000;
  int bpm = 120;
  int preset = 24;
  bool noteOff = true;

  bool _isPlaying = false;
  bool _pcmSoundLoaded = false;
  bool _soundFontLoaded = false;
  int _remainingFrames = 0;
  int _currentNote = -1;
  int _currentNoteGeneratedSamples = 0;

  @override
  void initState() {
    super.initState();

    // DartMeltySoundfont
    _loadRenderer().then((_) {
      _soundFontLoaded = true;
      print("Soundfont loaded");
      setState(() {});
    });

    // FlutterPcmSound
    _loadPcmSound();
    _pcmSoundLoaded = true;
  }

  void _loadPcmSound() {
    FlutterPcmSound.setLogLevel(LogLevel.verbose);
    FlutterPcmSound.setup(sampleRate: sampleRate, channelCount: 1);
    FlutterPcmSound.setFeedThreshold(feedThreshold);
    FlutterPcmSound.setFeedCallback(onFeed);
  }

  Future<void> _loadRenderer() async {
    _renderer = AudioRenderer();
    return _renderer!.loadSoundfont();
  }

  @override
  void dispose() {
    FlutterPcmSound.release();
    super.dispose();
  }

  List<AudioRendererEvent> getEventsToRender() {
    List<AudioRendererEvent> events = List.empty(growable: true);

    double noteLenghtInSeconds = 60 / bpm;
    int noteLenghtInSamples = (noteLenghtInSeconds * sampleRate).round();

    int samplesToGenerate = max(noteLenghtInSamples - _currentNoteGeneratedSamples, 0);
    while (samplesToGenerate <= newBufferLength) {
      if (noteOff) {
        events.add(NoteOff(sample: samplesToGenerate, key: notes[_currentNote % notes.length]));
      }
      _currentNote++;
      events.add(NoteOn(sample: samplesToGenerate, key: notes[_currentNote % notes.length]));
      _currentNoteGeneratedSamples = 0;
      samplesToGenerate += noteLenghtInSamples;
    }
    _currentNoteGeneratedSamples += min(noteLenghtInSamples - (samplesToGenerate - newBufferLength), newBufferLength);
    return events;
  }

  void onFeed(int remainingFrames) async {
    final startTime = DateTime.now();
    setState(() {
      _remainingFrames = remainingFrames;
    });

    final startEvents = DateTime.now();
    final events = getEventsToRender();
    final elapsedEvents = DateTime.now().difference(startEvents);

    final startRender = DateTime.now();
    final buf16 = await _renderer!.render(events);
    final elapsedRender = DateTime.now().difference(startRender);

    final startfeed = DateTime.now();
    await FlutterPcmSound.feed(PcmArrayInt16(bytes: buf16.bytes));
    final elapsedfeed = DateTime.now().difference(startfeed);
    final elapsed = DateTime.now().difference(startTime);
    print(
        "👹 Total ${elapsed.inMilliseconds} ${sampleRate * elapsed.inMilliseconds / 1000} events ${elapsedEvents.inMilliseconds} render ${elapsedRender.inMilliseconds} feed ${elapsedfeed.inMilliseconds}");
  }

  Future<void> _play() async {
    setPreset(preset);
    // start playing audio
    await FlutterPcmSound.play();

    setState(() {
      _isPlaying = true;
    });
  }

  Future<void> _pause() async {
    await FlutterPcmSound.pause();
    setState(() {
      _isPlaying = false;
    });
  }

  void setPreset(int preset) {
    _renderer!.setPreset(preset);
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (!_pcmSoundLoaded || !_soundFontLoaded) {
      child = const Text("initializing...");
    } else {
      child = Center(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: ElevatedButton(
                child: Text(_isPlaying ? "Pause" : "Play"),
                onPressed: () => _isPlaying ? _pause() : _play(),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Switch(value: noteOff, onChanged: (value) => noteOff = value),
                Text("Note Off"),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text("Remaining Frames $_remainingFrames"),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Text("BPM $bpm"),
                  Row(
                    children: [
                      ElevatedButton(
                        child: Text("-"),
                        onPressed: () => setState(() => bpm = (bpm - 1).clamp(10, 600).round()),
                      ),
                      Expanded(
                        child: Slider(
                          min: 10,
                          max: 600,
                          value: bpm.toDouble(),
                          onChanged: (value) {
                            setState(() => bpm = value.round());
                          },
                        ),
                      ),
                      ElevatedButton(
                        child: Text("+"),
                        onPressed: () => setState(() => bpm = (bpm + 1).clamp(10, 600).round()),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Text("Preset $preset"),
                  Row(
                    children: [
                      ElevatedButton(
                        child: Text("-"),
                        onPressed: () {
                          setState(() => preset = (preset - 1).clamp(0, 277).round());
                          setPreset(preset);
                        },
                      ),
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: 277,
                          value: preset.toDouble(),
                          onChanged: (value) {
                            setState(() => preset = value.round());
                            setPreset(value.round());
                          },
                        ),
                      ),
                      ElevatedButton(
                        child: Text("+"),
                        onPressed: () {
                          setState(() => preset = (preset + 1).clamp(0, 277).round());
                          setPreset(preset.round());
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          ],
        ),
      );
    }
    return MaterialApp(
        home: Scaffold(
      appBar: AppBar(title: const Text('Soundfont')),
      body: child,
    ));
  }
}
