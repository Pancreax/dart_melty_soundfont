import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';
import 'package:flutter/services.dart';

sealed class AudioRendererEvent {
  AudioRendererEvent({required this.sample});
  final int sample;
  void render(Synthesizer synth);
}

class NoteOn extends AudioRendererEvent {
  final int key;

  NoteOn({required super.sample, required this.key});

  @override
  void render(Synthesizer synth) {
    synth.noteOn(channel: 0, key: key, velocity: 126);
  }
}

class NoteOff extends AudioRendererEvent {
  final int key;

  NoteOff({required super.sample, required this.key});

  @override
  void render(Synthesizer synth) {
    synth.noteOff(channel: 0, key: key);
  }
}

class AudioRenderer {
  //String _asset = 'assets/TimGM6mbEdit.sf2';
  String _asset = 'assets/best_soundfont.sf2';

  final int sampleRate;
  final int bufferSizeInSamples;
  late final ArrayInt16 _buffer = ArrayInt16.zeros(numShorts: bufferSizeInSamples);
  Synthesizer? _synth;

  int alltimeSamples = 0;

  AudioRenderer({required this.bufferSizeInSamples, required this.sampleRate});

  void setPreset(int preset) {
    _synth!.selectPreset(channel: 0, preset: preset);
  }

  Future<void> loadSoundfont() async {
    ByteData bytes = await rootBundle.load(_asset);
    _synth = Synthesizer.loadByteData(bytes, SynthesizerSettings(enableReverbAndChorus: false));

    // print available instruments
    List<Preset> p = _synth!.soundFont.presets;
    for (int i = 0; i < p.length; i++) {
      String instrumentName = p[i].regions.isNotEmpty ? p[i].regions[0].instrument.name : "N/A";
      print('[preset $i] name: ${p[i].name} instrument: $instrumentName');
    }

    return Future<void>.value(null);
  }

  Future<ArrayInt16> render(List<AudioRendererEvent> events) async {
    final startBlockedRender = DateTime.now();
    int lastSample = 0;
    for (final event in events) {
      final lenght = event.sample - lastSample;
      if (lenght > 0) {
        _synth!.renderMonoInt16(_buffer, offset: lastSample, length: lenght);
      }
      event.render(_synth!);
      lastSample = event.sample;
    }
    _synth!.renderMonoInt16(_buffer, offset: lastSample);
    final elapsedBlockedRender = DateTime.now().difference(startBlockedRender);
    print("👹👹 blocking render ${elapsedBlockedRender.inMilliseconds}");
    return _buffer;
  }
}
