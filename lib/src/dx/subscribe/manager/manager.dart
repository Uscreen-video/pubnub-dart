import 'dart:async';

import 'package:pubnub/src/core/core.dart';
import 'package:pubnub/src/dx/_endpoints/subscribe.dart';
import 'package:pubnub/src/state_machine/state_machine.dart';

import 'exceptions.dart';

class SubscriptionManager {
  Core core;
  Keyset keyset;

  StreamController<dynamic> _messagesController = StreamController.broadcast();
  Stream<dynamic> get messages => _messagesController.stream;

  Blueprint<Symbol, Map<Symbol, dynamic>> _RequestMachine;
  Blueprint<Symbol, Map<Symbol, dynamic>> _SubscriptionMachine;

  StateMachine<Symbol, Map<Symbol, dynamic>> _machine;

  SubscriptionManager(this.core, this.keyset)
      : _RequestMachine = Blueprint<Symbol, Map<Symbol, dynamic>>()
          ..define(#reject, from: [#pending], to: #rejected)
          ..define(#resolve, from: [#pending], to: #resolved)
          ..define(#timeout, from: [#pending], to: #rejected)
          ..when(#resolved, #enters).exit(withPayload: true)
          ..when(#rejected, #enters).exit(withPayload: true)
          ..when(null, #exits).send(#timeout,
              payload: SubscribeTimeoutException(),
              after: Duration(seconds: 270))
          ..when(#pending, #enters).callback((ctx) async {
            SubscribeParams params = ctx.payload;

            var handler = await core.networking.handle(params.toRequest());

            ctx.update({#handler: handler});

            handler.text().then((result) {
              ctx.machine.send(#resolve, result);
            }).catchError((error) {
              ctx.machine.send(#reject, error);
            });
          })
          ..when(null, #enters).callback((ctx) {
            ctx.context[#handler]?.cancel();
          }),
        _SubscriptionMachine = Blueprint<Symbol, Map<Symbol, dynamic>>()
          ..define(#fetch,
              from: [#state.idle, #state.fetching], to: #state.fetching)
          ..define(#idle, from: [#state.fetching, #state.idle], to: #state.idle)
          ..define(#update,
              from: [#state.idle, #state.fetching], to: #state.idle)
          ..when(null, #exits).callback((ctx) {
            ctx.update(ctx.payload);
          })
          ..when(#state.idle, #enters).callback((ctx) {
            if (ctx.event == #update) {
              var newContext = <Symbol, dynamic>{
                ...ctx.context,
                ...ctx.payload
              };
              ctx.update(newContext);

              if (newContext[#isEnabled] == true &&
                  (newContext[#channels].length > 0 ||
                      newContext[#channelGroups].length > 0)) {
                ctx.machine.send(#fetch);
              }
            }
          }) {
    _SubscriptionMachine
      ..when(#state.fetching).machine('request', _RequestMachine,
          onBuild: (m, sm) {
        var params = SubscribeParams(keyset, m.context[#timetoken].value,
            region: m.context[#region],
            channels: m.context[#channels],
            channelGroups: m.context[#channelGroups]);

        sm.enter(#pending, params);
      }, onExit: (ctx, m, sm) async {
        switch (ctx.exiting) {
          case #resolved:
            var object = await core.parser.decode(ctx.payload);
            var result = SubscribeResult.fromJson(object);

            await _messagesController
                .addStream(Stream.fromIterable(result.messages));

            m.send(#update,
                {#timetoken: result.timetoken, #region: result.region});
            break;
          case #rejected:
            if (ctx.payload is SubscribeTimeoutException) {
              m.send(#update, {});
            }
            break;
        }
      });

    _machine = _SubscriptionMachine.build();

    _machine.enter(#state.idle, {
      #channels: Set<String>(),
      #channelGroups: Set<String>(),
      #timetoken: Timetoken(0),
      #region: null,
    });
  }

  void update(Map<Symbol, dynamic> Function(Map<Symbol, dynamic> ctx) cb) {
    if (_machine.state != #state.idle) {
      _machine.send(#fail, SubscribeOutdatedException());
    }

    _machine.send(#update, cb(_machine.context));
  }
}
