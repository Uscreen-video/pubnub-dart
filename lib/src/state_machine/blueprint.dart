import 'state_machine.dart';
import 'effect.dart';

import 'effects/send.dart';
import 'effects/exit.dart';
import 'effects/machine.dart';
import 'effects/callback.dart';

class Definition<State> {
  List<State> from;
  State to;
  Symbol event;
  Blueprint machine;
}

class ReporterDefinition {
  Symbol edge;
  dynamic state;
  Effect effect;
}

class BlueprintFactory<State, Context> {
  Blueprint blueprint;
  State state;
  List<Symbol> edges;

  BlueprintFactory(this.blueprint, this.state, this.edges);

  void _addEffect(Effect effect) {
    for (var edge in edges) {
      blueprint._effects.add(ReporterDefinition()
        ..edge = edge
        ..state = state
        ..effect = effect);
    }
  }

  void callback(Callback<State, Context> callback) =>
      _addEffect(CallbackEffect<State, Context>(callback));
  void send(Symbol event, {dynamic payload, Duration after}) => _addEffect(
      SendEffect<State, Context>(event, payload: payload, after: after));
  void exit({Duration after, bool withPayload}) => _addEffect(
      ExitEffect<State, Context>(after: after, withPayload: withPayload));
  void effect(Effect effect) => _addEffect(effect);
  void machine<SState, SContext>(
          String name, Blueprint<SState, SContext> blueprint,
          {MachineCallbackWithCtx<State, Context, SState, SContext> onEnter,
          MachineCallbackWithCtx<State, Context, SState, SContext> onExit,
          MachineCallback<State, Context, SState, SContext> onBuild}) =>
      _addEffect(MachineEffect<State, Context, SState, SContext>(
          name, blueprint,
          onEnter: onEnter, onExit: onExit, onBuild: onBuild));
}

class Blueprint<State, Context> {
  List<Definition<State>> _definitions = [];
  List<ReporterDefinition> _effects = [];

  Blueprint();

  StateMachine build([StateMachine parent]) {
    var machine = StateMachine<State, Context>();
    if (parent != null) machine.parent = parent;

    _definitions.forEach((def) {
      machine.define(def.event, from: def.from, to: def.to);
    });

    _effects.forEach((def) {
      machine.when(def.state, def.edge, def.effect);
    });

    return machine;
  }

  void define(Symbol event, {List<State> from, State to, Blueprint machine}) {
    _definitions.add(Definition<State>()
      ..from = from
      ..to = to
      ..event = event
      ..machine = machine);
  }

  BlueprintFactory<State, Context> when<Payload>(State state, [Symbol edge]) {
    if (edge == null) {
      return BlueprintFactory<State, Context>(this, state, [#enters, #exits]);
    } else {
      return BlueprintFactory<State, Context>(this, state, [edge]);
    }
  }
}
