///
//  Generated code. Do not modify.
//  source: scribe.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class JobStatus extends $pb.ProtobufEnum {
  static const JobStatus JOB_STATUS_UNSPECIFIED = JobStatus._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'JOB_STATUS_UNSPECIFIED');
  static const JobStatus QUEUED = JobStatus._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'QUEUED');
  static const JobStatus RUNNING = JobStatus._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'RUNNING');
  static const JobStatus COMPLETED = JobStatus._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPLETED');
  static const JobStatus FAILED = JobStatus._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FAILED');
  static const JobStatus CANCELED = JobStatus._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CANCELED');

  static const $core.List<JobStatus> values = <JobStatus> [
    JOB_STATUS_UNSPECIFIED,
    QUEUED,
    RUNNING,
    COMPLETED,
    FAILED,
    CANCELED,
  ];

  static final $core.Map<$core.int, JobStatus> _byValue = $pb.ProtobufEnum.initByValue(values);
  static JobStatus? valueOf($core.int value) => _byValue[value];

  const JobStatus._($core.int v, $core.String n) : super(v, n);
}

class DownloadStatus extends $pb.ProtobufEnum {
  static const DownloadStatus DOWNLOAD_STATUS_UNSPECIFIED = DownloadStatus._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DOWNLOAD_STATUS_UNSPECIFIED');
  static const DownloadStatus DOWNLOAD_STARTING = DownloadStatus._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DOWNLOAD_STARTING');
  static const DownloadStatus DOWNLOAD_DOWNLOADING = DownloadStatus._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DOWNLOAD_DOWNLOADING');
  static const DownloadStatus DOWNLOAD_COMPLETE = DownloadStatus._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DOWNLOAD_COMPLETE');
  static const DownloadStatus DOWNLOAD_FAILED = DownloadStatus._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DOWNLOAD_FAILED');
  static const DownloadStatus DOWNLOAD_CANCELED = DownloadStatus._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DOWNLOAD_CANCELED');

  static const $core.List<DownloadStatus> values = <DownloadStatus> [
    DOWNLOAD_STATUS_UNSPECIFIED,
    DOWNLOAD_STARTING,
    DOWNLOAD_DOWNLOADING,
    DOWNLOAD_COMPLETE,
    DOWNLOAD_FAILED,
    DOWNLOAD_CANCELED,
  ];

  static final $core.Map<$core.int, DownloadStatus> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DownloadStatus? valueOf($core.int value) => _byValue[value];

  const DownloadStatus._($core.int v, $core.String n) : super(v, n);
}

