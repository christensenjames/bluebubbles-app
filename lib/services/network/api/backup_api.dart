import 'package:bluebubbles/services/network/api/base_api.dart';
import 'package:dio/dio.dart';

class BackupApi {
  final BaseApi _svc;

  BackupApi(this._svc);

  /// Get backup theme JSON, if any
  Future<Response> getTheme({CancelToken? cancelToken}) async {
    return _svc.runApiGuarded(() async {
      final response = await _svc.dio.get(
        "${_svc.apiRoot}/backup/theme",
        cancelToken: cancelToken,
      );
      return _svc.returnSuccessOrError(response);
    });
  }

  /// Set theme backup with the provided [json]
  Future<Response> setTheme(String name, Map<String, dynamic> json, {CancelToken? cancelToken}) async {
    return _svc.runApiGuarded(() async {
      final response = await _svc.dio.post(
        "${_svc.apiRoot}/backup/theme",
        data: {"name": name, "data": json},
        cancelToken: cancelToken,
      );
      return _svc.returnSuccessOrError(response);
    });
  }

  /// Delete theme backup
  Future<Response> deleteTheme(String name, {CancelToken? cancelToken}) async {
    return _svc.runApiGuarded(() async {
      final response = await _svc.dio.delete(
        "${_svc.apiRoot}/backup/theme",
        data: {"name": name},
        cancelToken: cancelToken,
      );
      return _svc.returnSuccessOrError(response);
    });
  }

  /// Get settings backup, if any
  Future<Response> getSettings({CancelToken? cancelToken}) async {
    return _svc.runApiGuarded(() async {
      final response = await _svc.dio.get(
        "${_svc.apiRoot}/backup/settings",
        cancelToken: cancelToken,
      );
      return _svc.returnSuccessOrError(response);
    });
  }

  /// Delete settings backup
  Future<Response> deleteSettings(String name, {CancelToken? cancelToken}) async {
    return _svc.runApiGuarded(() async {
      final response = await _svc.dio.delete(
        "${_svc.apiRoot}/backup/settings",
        data: {"name": name},
        cancelToken: cancelToken,
      );
      return _svc.returnSuccessOrError(response);
    });
  }

  /// Set settings backup with the provided [json]
  Future<Response> setSettings(String name, Map<String, dynamic> json, {CancelToken? cancelToken}) async {
    return _svc.runApiGuarded(() async {
      final response = await _svc.dio.post(
        "${_svc.apiRoot}/backup/settings",
        data: {"name": name, "data": json},
        cancelToken: cancelToken,
      );
      return _svc.returnSuccessOrError(response);
    });
  }
}
