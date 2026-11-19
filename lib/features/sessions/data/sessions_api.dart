import 'package:dio/dio.dart';

import 'dto/discoverable_session.dart';
import 'dto/join_session_request.dart';
import 'dto/join_session_response.dart';
import 'dto/public_room_info.dart';

abstract interface class SessionsApi {
  Future<JoinSessionResponse> join(JoinSessionRequest request);
  Future<List<DiscoverableSession>> discover();
  Future<JoinSessionResponse> joinById(String sessionId);
  Future<PublicRoomInfo> getPublicRoom();
}

class DioSessionsApi implements SessionsApi {
  const DioSessionsApi(this._dio);

  final Dio _dio;

  @override
  Future<JoinSessionResponse> join(JoinSessionRequest request) async {
    final response = await _dio.post<Map<String, Object?>>(
      '/api/sessions/join',
      data: request.toJson(),
    );
    return JoinSessionResponse.fromJson(response.data!);
  }

  @override
  Future<List<DiscoverableSession>> discover() async {
    final response = await _dio.get<List<Object?>>('/api/sessions/discoverable');
    return (response.data ?? const [])
        .whereType<Map>()
        .map((entry) => DiscoverableSession.fromJson(Map<String, Object?>.from(entry)))
        .toList();
  }

  @override
  Future<JoinSessionResponse> joinById(String sessionId) async {
    final response = await _dio.post<Map<String, Object?>>(
      '/api/sessions/$sessionId/join',
    );
    return JoinSessionResponse.fromJson(response.data!);
  }

  @override
  Future<PublicRoomInfo> getPublicRoom() async {
    final response = await _dio.get<Map<String, Object?>>('/api/public-room');
    return PublicRoomInfo.fromJson(response.data!);
  }
}
