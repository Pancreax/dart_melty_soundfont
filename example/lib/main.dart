// ignore_for_file: avoid_print

import 'dart:typed_data'; // for Uint8List
import 'dart:ui';

import 'package:dart_melty_soundfont/preset.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

import 'package:dart_melty_soundfont/synthesizer.dart';
import 'package:dart_melty_soundfont/synthesizer_settings.dart';
import 'package:dart_melty_soundfont/audio_renderer_ex.dart';
import 'package:dart_melty_soundfont/array_int16.dart';

//String asset = 'assets/TimGM6mbEdit.sf2';
String asset = 'assets/best_soundfont.sf2';
List<int> notes = [60, 62, 64, 65, 67, 69, 71, 72];

void main() => runApp(const MeltyApp());

class MeltyApp extends StatefulWidget {
  const MeltyApp({Key? key}) : super(key: key);

  @override
  State<MeltyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MeltyApp> {
  Synthesizer? _synth;

  int sampleRate = 44100;
  int feedThreshold = 8000;
  int newBufferLength = 12000;
  int bpm = 120;
  int preset = 147;
  bool noteOff = true;

  bool _isPlaying = false;
  bool _pcmSoundLoaded = false;
  bool _soundFontLoaded = false;
  int _remainingFrames = 0;
  int _currentNote = 0;
  int _currentNoteSamplesLeft = 0;
  int _allTimeSampleCount = 0;

  @override
  void initState() {
    super.initState();

    // DartMeltySoundfont
    _loadSoundfont().then((_) {
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

  Future<void> _loadSoundfont() async {
    ByteData bytes = await rootBundle.load(asset);
    _synth = Synthesizer.loadByteData(bytes, SynthesizerSettings());

    // print available instruments
    List<Preset> p = _synth!.soundFont.presets;
    for (int i = 0; i < p.length; i++) {
      String instrumentName = p[i].regions.isNotEmpty ? p[i].regions[0].instrument.name : "N/A";
      print('[preset $i] name: ${p[i].name} instrument: $instrumentName');
    }

    return Future<void>.value(null);
  }

  @override
  void dispose() {
    FlutterPcmSound.release();
    super.dispose();
  }

  void nextNote() {
    _currentNote = _currentNote + 1;
  }

  ({ArrayInt16 nextBuffer, int samplesLeftFromCurrentNote}) renderNextBuffer(int samplesToRenderFromLastNote) {
    ArrayInt16 newBuffer = ArrayInt16.zeros(numShorts: newBufferLength);
    double noteLenghtInSeconds = 60 / bpm;
    int noteLenghtInSamples = (noteLenghtInSeconds * sampleRate).round();

    int generatedSamples = 0;

    if (samplesToRenderFromLastNote > newBufferLength) {
      print("👹 1 BIG note! rendering $newBufferLength samples");
      _allTimeSampleCount += newBuffer.bytes.lengthInBytes ~/ 2;
      _synth!.renderMonoInt16(newBuffer);
      int noteSamplesLeft = samplesToRenderFromLastNote - newBufferLength;
      return (nextBuffer: newBuffer, samplesLeftFromCurrentNote: noteSamplesLeft);
    } else if (samplesToRenderFromLastNote > 0) {
      print("👹 2 end of big note rendering $samplesToRenderFromLastNote samples");
      final bufferView = ByteData.sublistView(newBuffer.bytes, 0, samplesToRenderFromLastNote * 2);
      final arrayView = ArrayInt16(bytes: bufferView);
      _allTimeSampleCount += arrayView.bytes.lengthInBytes ~/ 2;
      _synth!.renderMonoInt16(arrayView);
      print("👹 NOTE OFF ${_currentNote % notes.length} sample $_allTimeSampleCount");
      if (noteOff) {
        _synth!.noteOff(channel: 0, key: notes[_currentNote % notes.length]);
      }
      nextNote();
      generatedSamples = samplesToRenderFromLastNote;
    }

    while (true) {
      print("👹👹 NOTE ON ${_currentNote % notes.length} sample $_allTimeSampleCount");
      _synth!.noteOn(channel: 0, key: notes[_currentNote % notes.length], velocity: 127);
      if (noteLenghtInSamples + generatedSamples >= newBufferLength) {
        final samplesToGenerate = newBufferLength - generatedSamples;
        print("👹 3 last note rendering $samplesToGenerate samples");
        int noteSamplesLeft = noteLenghtInSamples - samplesToGenerate;
        final bufferView = ByteData.sublistView(newBuffer.bytes, generatedSamples * 2);
        final arrayView = ArrayInt16(bytes: bufferView);
        _allTimeSampleCount += arrayView.bytes.lengthInBytes ~/ 2;
        _synth!.renderMonoInt16(arrayView);
        return (nextBuffer: newBuffer, samplesLeftFromCurrentNote: noteSamplesLeft);
      } else {
        final start = generatedSamples;
        final end = generatedSamples + noteLenghtInSamples;
        print("👹 4 middle note rendering ${end - start} ${noteLenghtInSamples} samples");
        final bufferView = ByteData.sublistView(newBuffer.bytes, start * 2, end * 2);
        final arrayView = ArrayInt16(bytes: bufferView);
        _allTimeSampleCount += arrayView.bytes.lengthInBytes ~/ 2;
        _synth!.renderMonoInt16(arrayView);
        print("👹👹 NOTE OFF ${_currentNote % notes.length} sample $_allTimeSampleCount");
        if (noteOff) {
          _synth!.noteOff(channel: 0, key: notes[_currentNote % notes.length]);
        }
        nextNote();
        generatedSamples += noteLenghtInSamples;
      }
    }
  }

  void onFeed(int remainingFrames) async {
    setState(() {
      _remainingFrames = remainingFrames;
    });

    final (nextBuffer: buf16, samplesLeftFromCurrentNote: samplesLeft) = renderNextBuffer(_currentNoteSamplesLeft);
    _currentNoteSamplesLeft = samplesLeft;
    await FlutterPcmSound.feed(PcmArrayInt16(bytes: buf16.bytes));
  }

  Future<void> _play() async {
    //setPreset(preset);
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
    // turnOff all notes
    _synth!.noteOffAll();

    // select preset (i.e. instrument)
    _synth!.selectPreset(channel: 0, preset: preset);
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
                            bpm = value.round();
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
                            preset = value.round();
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
