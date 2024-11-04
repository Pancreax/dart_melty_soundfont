import 'dart:async';
import 'dart:isolate';

import 'package:async/async.dart';
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

sealed class AudioRendererMessage {}

class SetPresetMessage implements AudioRendererMessage {
  final int preset;

  SetPresetMessage(this.preset);
}

class SetupRendererMessage implements AudioRendererMessage {
  final ByteData soundfontBytes;
  final int bufferSizeInSamples;

  SetupRendererMessage(this.soundfontBytes, this.bufferSizeInSamples);
}

class RenderEventsMessage implements AudioRendererMessage {
  final List<AudioRendererEvent> events;

  RenderEventsMessage(this.events);
}

class AudioRenderer {
  //String _asset = 'assets/TimGM6mbEdit.sf2';
  String _asset = 'assets/best_soundfont.sf2';

  late final SendPort _commands;
  late final StreamQueue _responsesQueue;

  static void _startRenderIsolate(SendPort sendPort) {
    ArrayInt16? _buffer;
    Synthesizer? _synth;

    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    receivePort.listen((message) {
      if (message is! AudioRendererMessage) {
        return;
      }

      switch (message) {
        case SetPresetMessage(preset: final preset):
          _synth!.selectPreset(channel: 0, preset: preset);

        case SetupRendererMessage(soundfontBytes: final soundfontBytes, bufferSizeInSamples: final bufferSizeInSamples):
          _synth = Synthesizer.loadByteData(soundfontBytes, SynthesizerSettings(enableReverbAndChorus: false));
          _buffer = ArrayInt16.zeros(numShorts: bufferSizeInSamples);
          sendPort.send(_synth!.soundFont.presets);

        case RenderEventsMessage(events: final events):
          int lastSample = 0;
          for (final event in events) {
            final lenght = event.sample - lastSample;
            if (lenght > 0) {
              _synth!.renderMonoInt16(_buffer!, offset: lastSample, length: lenght);
            }
            event.render(_synth!);
            lastSample = event.sample;
          }
          _synth!.renderMonoInt16(_buffer!, offset: lastSample);
          final transferable = TransferableTypedData.fromList([_buffer!.bytes]);
          sendPort.send(transferable);
      }
    });
  }

  void setPreset(int preset) {
    _commands.send(SetPresetMessage(preset));
  }

  Future<void> loadSoundfont() async {
    final responsesPort = ReceivePort();
    _responsesQueue = StreamQueue(responsesPort);
    Isolate.spawn(_startRenderIsolate, responsesPort.sendPort);
    final initialMessage = await _responsesQueue.next;
    _commands = initialMessage as SendPort;

    ByteData bytes = await rootBundle.load(_asset);
    final bufferSizeInSamples = 6000;
    _commands.send(SetupRendererMessage(bytes, bufferSizeInSamples));

    // print available instruments
    List<Preset> p = await _responsesQueue.next;
    for (int i = 0; i < p.length; i++) {
      String instrumentName = p[i].regions.isNotEmpty ? p[i].regions[0].instrument.name : "N/A";
      print('[preset $i] name: ${p[i].name} instrument: $instrumentName');
    }
  }

  Future<ArrayInt16> render(List<AudioRendererEvent> events) async {
    _commands.send(RenderEventsMessage(events));
    final message = await _responsesQueue.next;
    final bytes = (message as TransferableTypedData).materialize().asByteData();
    return ArrayInt16(bytes: bytes);
  }
}
