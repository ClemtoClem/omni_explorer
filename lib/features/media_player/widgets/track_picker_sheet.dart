/// @file track_picker_sheet.dart
/// @brief Sélecteur de piste audio et de sous-titres.

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

class TrackPickerSheet extends StatelessWidget {
  final Tracks tracks;
  final AudioTrack currentAudio;
  final SubtitleTrack currentSubtitle;
  final ValueChanged<AudioTrack> onAudioSelected;
  final ValueChanged<SubtitleTrack> onSubtitleSelected;

  const TrackPickerSheet({
    super.key,
    required this.tracks,
    required this.currentAudio,
    required this.currentSubtitle,
    required this.onAudioSelected,
    required this.onSubtitleSelected,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TabBar(tabs: [
                Tab(text: 'Audio', icon: Icon(Icons.audiotrack_rounded)),
                Tab(text: 'Sous-titres', icon: Icon(Icons.subtitles_rounded)),
              ]),
              SizedBox(
                height: 320,
                child: TabBarView(children: [
                  _AudioList(
                    tracks: tracks.audio,
                    current: currentAudio,
                    onSelected: (t) {
                      Navigator.pop(context);
                      onAudioSelected(t);
                    },
                  ),
                  _SubtitleList(
                    tracks: tracks.subtitle,
                    current: currentSubtitle,
                    onSelected: (t) {
                      Navigator.pop(context);
                      onSubtitleSelected(t);
                    },
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AudioList extends StatelessWidget {
  final List<AudioTrack> tracks;
  final AudioTrack current;
  final ValueChanged<AudioTrack> onSelected;
  const _AudioList(
      {required this.tracks, required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const Center(child: Text('Aucune piste audio'));
    }
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (_, i) {
        final t = tracks[i];
        final selected = t.id == current.id;
        final title = t.title ?? t.language ?? t.id;
        return ListTile(
          leading: Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: selected ? Colors.lightBlueAccent : null,
          ),
          title: Text(title),
          subtitle: t.language != null ? Text(t.language!) : null,
          onTap: () => onSelected(t),
        );
      },
    );
  }
}

class _SubtitleList extends StatelessWidget {
  final List<SubtitleTrack> tracks;
  final SubtitleTrack current;
  final ValueChanged<SubtitleTrack> onSelected;
  const _SubtitleList(
      {required this.tracks, required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return const Center(child: Text('Aucun sous-titre'));
    }
    return ListView.builder(
      itemCount: tracks.length,
      itemBuilder: (_, i) {
        final t = tracks[i];
        final selected = t.id == current.id;
        final title = t.title ?? t.language ?? t.id;
        return ListTile(
          leading: Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            color: selected ? Colors.lightBlueAccent : null,
          ),
          title: Text(title),
          subtitle: t.language != null ? Text(t.language!) : null,
          onTap: () => onSelected(t),
        );
      },
    );
  }
}
