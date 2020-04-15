import 'package:pubnub/src/core/core.dart';
import 'package:pubnub/src/dx/_utils/utils.dart';

class SignalParams extends Parameters {
  Keyset keyset;
  String channel;
  String payload;

  SignalParams(this.keyset, this.channel, this.payload);

  Request toRequest() {
    Map<String, String> queryParameters = {
      if (keyset.authKey != null) 'auth': keyset.authKey,
      if (keyset.uuid != null) 'uuid': keyset.uuid.value,
    };

    return Request(
        type: RequestType.get,
        uri: Uri(pathSegments: [
          'signal',
          keyset.publishKey,
          keyset.subscribeKey,
          '0',
          channel,
          '0',
          payload
        ], queryParameters: queryParameters));
  }
}

class SignalResult extends Result {
  bool isError;
  String description;
  int timetoken;

  SignalResult();

  factory SignalResult.fromJson(dynamic object) {
    if (object is List) {
      return SignalResult()
        ..timetoken = int.tryParse(object[2])
        ..description = object[1]
        ..isError = object[0] == 0 ? false : true;
    }

    throw getExceptionFromDefaultResult(DefaultResult.fromJson(object));
  }
}
