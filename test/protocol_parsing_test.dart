import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:meshcore_open/connector/meshcore_protocol.dart';
import 'package:meshcore_open/models/channel_message.dart';
import 'package:meshcore_open/models/contact.dart';

void _writeCString(Uint8List buffer, int offset, String value) {
  final bytes = utf8.encode(value);
  buffer.setRange(offset, offset + bytes.length, bytes);
  if (offset + bytes.length < buffer.length) {
    buffer[offset + bytes.length] = 0;
  }
}

Uint8List _buildContactMessageFrame({
  required int code,
  required Uint8List senderPrefix,
  required int pathLen,
  required int txtType,
  required int timestampSeconds,
  required String text,
}) {
  final textBytes = utf8.encode(text);
  final isV3 = code == respCodeContactMsgRecvV3;
  final prefixOffset = isV3 ? 4 : 1;
  final baseTextOffset = prefixOffset + 6 + 1 + 1 + 4;
  final frame = Uint8List(baseTextOffset + textBytes.length + 1);
  frame[0] = code;
  if (isV3) {
    frame[1] = 0;
    frame[2] = 0;
    frame[3] = 0;
  }
  frame.setRange(prefixOffset, prefixOffset + 6, senderPrefix);
  frame[prefixOffset + 6] = pathLen;
  frame[prefixOffset + 7] = txtType;
  writeUint32LE(frame, prefixOffset + 8, timestampSeconds);
  frame.setRange(baseTextOffset, baseTextOffset + textBytes.length, textBytes);
  frame[frame.length - 1] = 0;
  return frame;
}

void main() {
  group('SelfInfo frame helpers', () {
    test('should read self info fields using protocol helpers', () {
      final frame = Uint8List(58 + 16);
      frame[0] = respCodeSelfInfo;
      frame[1] = 1;
      frame[2] = 20;
      frame[3] = 30;
      frame.setRange(4, 4 + pubKeySize, List.filled(pubKeySize, 0xAB));
      writeInt32LE(frame, 36, 12345678);
      writeInt32LE(frame, 40, -87654321);
      frame[44] = 0;
      frame[45] = 0;
      frame[46] = 0;
      frame[47] = 1;
      writeUint32LE(frame, 48, 915000);
      writeUint32LE(frame, 52, 125);
      frame[56] = 10;
      frame[57] = 5;
      _writeCString(frame, 58, 'TestNode');

      expect(readInt32LE(frame, 36), equals(12345678));
      expect(readInt32LE(frame, 40), equals(-87654321));
      expect(readUint32LE(frame, 48), equals(915000));
      expect(readUint32LE(frame, 52), equals(125));
      expect(readCString(frame, 58, frame.length - 58), equals('TestNode'));
    });
  });

  group('Contact response parsing', () {
    test('should parse Contact with correct field order', () {
      final frame = Uint8List(contactFrameSize);
      frame[0] = respCodeContact;
      frame.setRange(
        contactPubKeyOffset,
        contactPubKeyOffset + pubKeySize,
        List.filled(pubKeySize, 0xCD),
      );
      frame[contactTypeOffset] = 2;
      frame[contactFlagsOffset] = 0x01;
      frame[contactPathLenOffset] = 3;
      frame.setRange(contactPathOffset, contactPathOffset + 3, [1, 2, 3]);
      _writeCString(frame, contactNameOffset, 'ContactName');
      writeUint32LE(frame, contactTimestampOffset, 1704067200);
      writeInt32LE(frame, contactLatOffset, 40000000);
      writeInt32LE(frame, contactLonOffset, 0);
      writeUint32LE(frame, contactLastmodOffset, 1704153600);

      final result = Contact.fromFrame(frame);

      expect(result, isNotNull);
      expect(result!.publicKey.length, equals(32));
      expect(result.publicKey[0], equals(0xCD));
      expect(result.type, equals(2));
      expect(result.name, equals('ContactName'));
      expect(result.pathLength, equals(3));
      expect(result.lastSeen.millisecondsSinceEpoch, equals(1704153600 * 1000));
    });
  });

  group('Contact message parsing', () {
    test('should parse contact message text and prefix', () {
      final prefix = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]);
      final frame = _buildContactMessageFrame(
        code: respCodeContactMsgRecv,
        senderPrefix: prefix,
        pathLen: 3,
        txtType: txtTypePlain,
        timestampSeconds: 1704067200,
        text: 'Hello, World!',
      );

      final result = parseContactMessageText(frame);

      expect(result, isNotNull);
      expect(result!.senderPrefix, orderedEquals(prefix));
      expect(result.text, equals('Hello, World!'));
    });

    test('should parse v3 contact message format', () {
      final prefix = Uint8List.fromList([0x10, 0x11, 0x12, 0x13, 0x14, 0x15]);
      final frame = _buildContactMessageFrame(
        code: respCodeContactMsgRecvV3,
        senderPrefix: prefix,
        pathLen: 1,
        txtType: txtTypePlain,
        timestampSeconds: 1704067200,
        text: 'V3 message',
      );

      final result = parseContactMessageText(frame);

      expect(result, isNotNull);
      expect(result!.senderPrefix, orderedEquals(prefix));
      expect(result.text, equals('V3 message'));
    });

    test('should return null when text is empty', () {
      final frame = _buildContactMessageFrame(
        code: respCodeContactMsgRecv,
        senderPrefix: Uint8List(6),
        pathLen: 1,
        txtType: txtTypePlain,
        timestampSeconds: 0,
        text: '',
      );

      final result = parseContactMessageText(frame);

      expect(result, isNull);
    });
  });

  group('Channel message parsing', () {
    test('should parse channel message with sender name and text', () {
      final text = 'Alice: Channel message!';
      final textBytes = utf8.encode(text);
      final frame = Uint8List(8 + textBytes.length + 1);
      frame[0] = respCodeChannelMsgRecv;
      frame[1] = 2;
      frame[2] = 5;
      frame[3] = txtTypePlain;
      writeUint32LE(frame, 4, 1704153600);
      frame.setRange(8, 8 + textBytes.length, textBytes);
      frame[frame.length - 1] = 0;

      final result = ChannelMessage.fromFrame(frame);

      expect(result, isNotNull);
      expect(result!.channelIndex, equals(2));
      expect(result.pathLength, equals(5));
      expect(result.senderName, equals('Alice'));
      expect(result.text, equals('Channel message!'));
    });

    test('should ignore non-plain channel messages', () {
      final textBytes = utf8.encode('CLI output');
      final frame = Uint8List(8 + textBytes.length + 1);
      frame[0] = respCodeChannelMsgRecv;
      frame[1] = 255;
      frame[2] = 0;
      frame[3] = txtTypeCliData;
      writeUint32LE(frame, 4, 123456789);
      frame.setRange(8, 8 + textBytes.length, textBytes);
      frame[frame.length - 1] = 0;

      final result = ChannelMessage.fromFrame(frame);

      expect(result, isNull);
    });
  });

  group('Battery voltage helper', () {
    test('should read battery millivolts from uint16', () {
      final frame = Uint8List(3);
      frame[0] = respCodeBattAndStorage;
      frame[1] = 0x68;
      frame[2] = 0x10;

      expect(readUint16LE(frame, 1), equals(4200));
    });
  });

  group('CString helper', () {
    test('should read firmware build date', () {
      final frame = Uint8List(32);
      frame[0] = respCodeDeviceInfo;
      _writeCString(frame, 1, '2024-01-01');

      expect(readCString(frame, 1, frame.length - 1), equals('2024-01-01'));
    });

    test('should read long firmware date strings', () {
      final frame = Uint8List(64);
      frame[0] = respCodeDeviceInfo;
      _writeCString(frame, 1, 'Dec 31 2024 12:34:56 (git-abc1234)');

      expect(
        readCString(frame, 1, frame.length - 1),
        equals('Dec 31 2024 12:34:56 (git-abc1234)'),
      );
    });
  });
}
