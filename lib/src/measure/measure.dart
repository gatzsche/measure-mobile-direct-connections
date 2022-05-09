// @license
// Copyright (c) 2019 - 2022 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'package:flutter/material.dart';
import 'package:gg_value/gg_value.dart';

import '../com/fake/fake_service.dart';
import '../com/shared/connection.dart';
import '../com/shared/network_service.dart';
import 'data_recorder.dart';
import 'types.dart';

class MeasureLogMessages {
  static String start(MeasurmentRole role) => 'Start measurement as $role';
  static String measure(MeasurmentRole role) => 'Measure as $role';
  static String stop(MeasurmentRole role) => 'Stop measurement as $role';
}

class Measure {
  Measure({
    required this.role,
    this.log,
    required this.networkService,
  }) {
    _initIsMeasuring();
  }

  // ...........................................................................
  @mustCallSuper
  void dispose() {
    for (final d in _dispose.reversed) {
      d();
    }
  }

  // ...........................................................................
  final Log? log;
  final NetworkService networkService;
  final MeasurmentRole role;

  // ...........................................................................
  Future<void> start() async {
    if (_connection != null) {
      return;
    }
    _logStart();
    await _connect();
  }

  // ...........................................................................
  Future<void> measure() async {
    assert(!_isMeasuring);
    assert(_connection != null);

    _logMeasure();
    _isMeasuring = true;

    _dataRecorder = DataRecorder(
      connection: _connection!,
      role: role,
      log: log,
    );

    await _dataRecorder!.record();

    if (_dataRecorder?.resultCsv != null) {
      _measurmentResults.add(_dataRecorder!.resultCsv!);
    }
    _isMeasuring = false;
  }

  // ...........................................................................
  Future<void> stop() async {
    assert(_connection != null);

    _logStop();

    _dataRecorder?.stop();
    _dataRecorder = null;

    await _disconnect();
    _connection = null;
  }

  // ...........................................................................
  List<String> get measurmentResults => _measurmentResults;

  // ...........................................................................
  final isMeasuring = GgValue<bool>(seed: false);
  void _initIsMeasuring() {
    _dispose.add(isMeasuring.dispose);
  }

  // ######################
  // Private
  // ######################

  final List<Function()> _dispose = [];
  final List<String> _measurmentResults = [];
  var _isMeasuring = false;
  Connection? _connection;

  // ...........................................................................
  DataRecorder? _dataRecorder;

  // ...........................................................................
  Future<void> _connect() async {
    await networkService.start();
    final connection = await networkService.firstConnection;
    _connection = connection;
  }

  // ...........................................................................
  Future<void> _disconnect() async {
    await networkService.stop();
  }

  // ...........................................................................
  void _logStart() => log?.call(MeasureLogMessages.start(role));
  void _logStop() => log?.call(MeasureLogMessages.stop(role));
  void _logMeasure() => log?.call(MeasureLogMessages.measure(role));
}

// #############################################################################

Measure exampleMeasureMaster({Log? log}) {
  return Measure(
    role: MeasurmentRole.master,
    log: log,
    networkService: FakeService.master,
  );
}

Measure exampleMeasureSlave({Log? log}) {
  return Measure(
    role: MeasurmentRole.slave,
    log: log,
    networkService: FakeService.slave,
  );
}
//
