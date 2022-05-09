// @license
// Copyright (c) 2019 - 2022 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:async';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../com/shared/connection.dart';
import '../utils/is_test.dart';
import '../utils/utils.dart';
import 'types.dart';

class Messages {
  static const packetStart = 'PacketStart';
  static const packetEnd = 'PacketEnd';
  static const acknowledgment = 'Acknowledgement';
}

const _oneKb = 1024;
const _oneMb = _oneKb * _oneKb;
const _tenMb = 10 * _oneMb;

class DataRecorder {
  DataRecorder({
    required this.connection,
    required this.role,
    this.log,
    this.maxNumMeasurements = 10,
    this.packageSizes = const [_oneKb, _oneMb, _tenMb],
  }) {
    _initMeasurementCycles();
  }

  // ...........................................................................
  void dispose() {
    for (final d in _dispose.reversed) {
      d();
    }
  }

  // ...........................................................................
  bool get isRunning => _isRunning;

  // ...........................................................................
  final Connection connection;
  final EndpointRole role;

  // ######################
  // Master
  // ######################

  /// Listen to incoming acknowledgments and start next measurement cycle then

  final int maxNumMeasurements;
  final Log? log;
  final List<int> packageSizes;

  Stream<int> get measurmentCycles => _measurmentCycles.stream;

  // ...........................................................................
  Future<void> get _waitForAcknowledgement => connection.receiveData.firstWhere(
        (event) {
          return event.string.startsWith(Messages.acknowledgment);
        },
      );

  // ...........................................................................
  Future<void> record() async {
    if (role == EndpointRole.master) {
      await _sendDataToSlaveAndWaitForAcknowledgement();
    } else {
      await _listenToDataFromMasterAndAcknowledge();
    }
  }

  // ...........................................................................
  Future<void> _listenToDataFromMasterAndAcknowledge() async {
    final s = connection.receiveData.listen(
      (data) {
        final str = data.string;
        if (str.endsWith(Messages.packetEnd)) {
          connection.sendData(Messages.acknowledgment.uint8List);
        }
      },
    );

    _dispose.add(s.cancel);
  }

  // ...........................................................................
  Future<void> _sendDataToSlaveAndWaitForAcknowledgement() async {
    _stop = false;

    _isRunning = true;

    for (final packageSize in packageSizes) {
      _initResultArray(packageSize);

      log?.call('Measuring data for packageSize $packageSize ...');

      for (var iteration = 0; iteration < maxNumMeasurements; iteration++) {
        if (_stop) {
          log?.call('Stopping measurment');
          break;
        }

        _measurmentCycles.add(iteration);
        _initBuffer(packageSize);
        _startTimeMeasurement();
        _sendDataToSlave();
        await _waitForAcknowledgement;
        _stopTimeMeasurement();
        _writeMeasuredTimes(packageSize);
      }
    }

    _isRunning = false;

    if (!_stop) {
      log?.call('Exporting Measurement Results');
      _exportMeasuredResults();
    }

    log?.call('Done.');
  }

  // ...........................................................................
  void stop() {
    _stop = true;
  }

  // ...........................................................................
  String? get resultCsv {
    return _resultCsv;
  }

  // ...........................................................................
  Uint8List? _buffer;
  void _initBuffer(int packageSize) {
    final builder = BytesBuilder();
    final bufferStartMsg = Messages.packetStart.uint8List;
    final bufferEndMsg = Messages.packetEnd.uint8List;
    final fillBytes = packageSize - bufferStartMsg.length - bufferEndMsg.length;

    builder.add(bufferStartMsg);

    final payload = ''.padRight(fillBytes, ' ');
    builder.add(payload.uint8List);
    builder.add(bufferEndMsg);

    _buffer = builder.takeBytes();
  }

  // ...........................................................................
  void _startTimeMeasurement() {
    _stopWatch.reset();
    _stopWatch.start();
  }

  // ...........................................................................
  Future<void> _sendDataToSlave() async {
    log?.call('Sending buffer of size ${_buffer!.lengthInBytes}...');
    await connection.sendData(_buffer!);
  }

  // ...........................................................................
  void _stopTimeMeasurement() {
    log?.call('Stop time measurement ...');
    _stopWatch.stop();
  }

  // ...........................................................................
  final Map<int, List<int>> _measurementResults = {};
  void _initResultArray(int packageSize) {
    _measurementResults[packageSize] = [];
  }

  // ...........................................................................
  void _writeMeasuredTimes(int packageSize) {
    final elapsedTime = _stopWatch.elapsed.inMicroseconds;
    _measurementResults[packageSize]!.add(elapsedTime);
  }

  // ...........................................................................
  String? _resultCsv;

  // ...........................................................................
  void _exportMeasuredResults() async {
    String csv = '';

    // table header
    /* csvContent += "Byte Size";
    csvContent += ",";
    for (var i = 0; i < maxNumMeasurements; i++) {
      csvContent += "${i + 1}";
      if (i < maxNumMeasurements - 1) {
        csvContent += ",";
      }
    }
    csvContent += "\n"; */

    // for each serial number,
    //   iterate the measurement results.
    //   i.e
    //   iterate each byte size of the measurement results
    //   get the measurement array for each byte size
    //   get the measurement out of the array

    //create csv table
    csv += 'Byte Sizes';
    csv += ',';
    for (var packageSize in packageSizes) {
      csv += '$packageSize';
      final isLast = packageSize == packageSizes.last;
      if (!isLast) {
        csv += ',';
      }
    }
    csv += '\n';

    for (var i = 0; i < maxNumMeasurements; i++) {
      var numOfIterations = i + 1;

      csv += '$numOfIterations';
      csv += ',';
      log?.call('Num: $numOfIterations');

      for (var packetSize in packageSizes) {
        final size = packetSize;
        final times = _measurementResults[packetSize]![i];
        final isLast = packetSize == packageSizes.last;

        csv += '$times';
        if (!isLast) {
          csv += ',';
        }

        log?.call('$size: $times');
      }

      final isLastRow = i == maxNumMeasurements - 1;
      if (!isLastRow) {
        csv += '\n';
      }
    }

    if (!isTest) {
      // coverage:ignore-start
      final prefs = await SharedPreferences.getInstance();
      prefs.setString('measurements.csv', csv);
      // coverage:ignore-end
    }

    _resultCsv = csv;

    // const path = '/Users/ajibade/Desktop/measurement_result.csv';
    // var myFile = File(path);
    // if (myFile.existsSync()) {
    //   myFile.deleteSync();
    //   myFile = File(path);
    // }
    // myFile.writeAsStringSync(_resultCsv);
  }

  // ...........................................................................
  final _stopWatch = Stopwatch();

  // ######################
  // Private
  // ######################

  final List<Function()> _dispose = [];

  bool _stop = false;
  bool _isRunning = false;
  final _measurmentCycles = StreamController<int>();
  void _initMeasurementCycles() {
    _dispose.add(_measurmentCycles.close);
  }
}

// #############################################################################
DataRecorder exampleMasterDataRecorder({Connection? connection}) =>
    DataRecorder(
      connection: connection ?? exampleConnection(),
      role: EndpointRole.master,
    );

// #############################################################################
DataRecorder exampleSlaveDataRecorder({Connection? connection}) => DataRecorder(
      connection: connection ?? exampleConnection(),
      role: EndpointRole.slave,
    );
