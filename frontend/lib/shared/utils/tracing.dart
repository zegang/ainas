import 'dart:developer' as developer;

class Tracing {
  /// Whether timeline tracing is enabled.
  static bool _enabled = false;

  /// Initialise tracing.
  /// Call once at app startup.
  static void init({bool enabled = true}) {
    _enabled = enabled;
    if (_enabled) {
      developer.postEvent('Flutter.Timeline', {
        'name': 'ainas-frontend',
      });
    }
  }

  /// Wrap a cohesive unit of work with a timeline flow.
  /// Creates a TimelineTask and emits start/finish events.
  static TraceFlow flow(String name, {Map<String, dynamic>? args}) {
    if (!_enabled) return TraceFlow._noop();
    final flow = TraceFlow._(name);
    flow.start(args: args);
    return flow;
  }

  /// Explicit begin / end for long-lived or cross-async operations.
  static void begin(String name, {Map<String, dynamic>? args}) {
    if (!_enabled) return;
    developer.Timeline.startSync(name, arguments: args);
  }

  static void end(String name) {
    if (!_enabled) return;
    developer.Timeline.finishSync();
  }

  static void set enabled(bool value) => _enabled = value;
  static bool get enabled => _enabled;
}

class TraceFlow {
  final String _name;
  final developer.TimelineTask _task;
  bool _finished = false;

  TraceFlow._(this._name) : _task = developer.TimelineTask();

  TraceFlow._noop() : _name = '', _task = developer.TimelineTask();

  void start({Map<String, dynamic>? args}) {
    _task.start(_name, arguments: args);
  }

  void step(String name, {Map<String, dynamic>? args}) {
    if (_finished) return;
    _task.instant(name, arguments: args);
  }

  void finish({Map<String, dynamic>? args}) {
    if (_finished) return;
    _finished = true;
    _task.finish(arguments: args);
  }
}
