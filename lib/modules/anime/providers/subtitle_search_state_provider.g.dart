// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subtitle_search_state_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SubtitleSearchStateNotifier)
final subtitleSearchStateProvider = SubtitleSearchStateNotifierFamily._();

final class SubtitleSearchStateNotifierProvider
    extends
        $NotifierProvider<SubtitleSearchStateNotifier, SubtitleSearchState> {
  SubtitleSearchStateNotifierProvider._({
    required SubtitleSearchStateNotifierFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'subtitleSearchStateProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$subtitleSearchStateNotifierHash();

  @override
  String toString() {
    return r'subtitleSearchStateProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SubtitleSearchStateNotifier create() => SubtitleSearchStateNotifier();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SubtitleSearchState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SubtitleSearchState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SubtitleSearchStateNotifierProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$subtitleSearchStateNotifierHash() =>
    r'72030c8fbd1790e4e32bb751c97076230bf68c53';

final class SubtitleSearchStateNotifierFamily extends $Family
    with
        $ClassFamilyOverride<
          SubtitleSearchStateNotifier,
          SubtitleSearchState,
          SubtitleSearchState,
          SubtitleSearchState,
          String
        > {
  SubtitleSearchStateNotifierFamily._()
    : super(
        retry: null,
        name: r'subtitleSearchStateProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  SubtitleSearchStateNotifierProvider call(String key) =>
      SubtitleSearchStateNotifierProvider._(argument: key, from: this);

  @override
  String toString() => r'subtitleSearchStateProvider';
}

abstract class _$SubtitleSearchStateNotifier
    extends $Notifier<SubtitleSearchState> {
  late final _$args = ref.$arg as String;
  String get key => _$args;

  SubtitleSearchState build(String key);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<SubtitleSearchState, SubtitleSearchState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SubtitleSearchState, SubtitleSearchState>,
              SubtitleSearchState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
