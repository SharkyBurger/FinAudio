import 'package:flutter/material.dart';
import '../services/google_auth_service.dart';
import '../services/player_service.dart';
import '../services/playlist_service.dart';
import '../services/settings_service.dart';
import '../ui/artist_screen.dart';

/// Opens an artist's profile page.
void openArtistPage({
  required BuildContext context,
  required String artistName,
  required PlayerService playerService,
  required GoogleAuthService authService,
  required PlaylistService playlistService,
  required SettingsService settingsService,
  String? channelId,
  String? initialImageUrl,
}) {
  if (artistName.trim().isEmpty) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ArtistScreen(
        artistName: artistName.trim(),
        channelId: channelId,
        initialImageUrl: initialImageUrl,
        playerService: playerService,
        authService: authService,
        playlistService: playlistService,
        settingsService: settingsService,
      ),
    ),
  );
}

/// If [artists] has 1 artist, directly navigates to their profile page.
/// If [artists] has multiple artists, opens a bottom sheet allowing the user
/// to select which collaborating artist they want to explore.
void navigateToArtistOrShowPicker({
  required BuildContext context,
  required List<String> artists,
  required PlayerService playerService,
  required GoogleAuthService authService,
  required PlaylistService playlistService,
  required SettingsService settingsService,
  String? trackTitle,
  String? initialImageUrl,
  Color? surfaceColor,
  Color? textColor,
  Color? accentColor,
}) {
  final cleanArtists = artists.map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
  if (cleanArtists.isEmpty) return;

  if (cleanArtists.length == 1) {
    openArtistPage(
      context: context,
      artistName: cleanArtists.first,
      playerService: playerService,
      authService: authService,
      playlistService: playlistService,
      settingsService: settingsService,
      initialImageUrl: initialImageUrl,
    );
    return;
  }

  showArtistPickerSheet(
    context: context,
    artists: cleanArtists,
    trackTitle: trackTitle,
    initialImageUrl: initialImageUrl,
    surfaceColor: surfaceColor,
    textColor: textColor,
    accentColor: accentColor,
    onSelectArtist: (selected) {
      openArtistPage(
        context: context,
        artistName: selected,
        playerService: playerService,
        authService: authService,
        playlistService: playlistService,
        settingsService: settingsService,
        initialImageUrl: initialImageUrl,
      );
    },
  );
}

/// Displays a modal bottom sheet listing collaborating artists on a song.
Future<void> showArtistPickerSheet({
  required BuildContext context,
  required List<String> artists,
  required void Function(String artistName) onSelectArtist,
  String? trackTitle,
  String? initialImageUrl,
  Color? surfaceColor,
  Color? textColor,
  Color? accentColor,
}) {
  final cleanArtists = artists.map((a) => a.trim()).where((a) => a.isNotEmpty).toList();
  if (cleanArtists.isEmpty) return Future.value();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final theme = Theme.of(context);
      final bg = surfaceColor ?? const Color(0xFF1E1E1E);
      final text = textColor ?? Colors.white;
      final accent = accentColor ?? theme.colorScheme.primary;

      return Material(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title and subtitle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Artists in this track',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: text,
                      ),
                    ),
                    if (trackTitle != null && trackTitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        trackTitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: text.withAlpha(160),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 8),

              // Artist list
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  itemCount: cleanArtists.length,
                  separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 1),
                  itemBuilder: (_, index) {
                    final artist = cleanArtists[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: accent.withAlpha(40),
                        child: Text(
                          artist.isNotEmpty ? artist[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      title: Text(
                        artist,
                        style: TextStyle(
                          color: text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      subtitle: Text(
                        'View artist profile',
                        style: TextStyle(
                          color: text.withAlpha(140),
                          fontSize: 12,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: text.withAlpha(140),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        onSelectArtist(artist);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
  );
}
