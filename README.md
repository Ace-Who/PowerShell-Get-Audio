# posh-Get-Audio

Extract and/or split audio stream from a media file.

## Usage

Extract audio streams from two .mp4 files and save as input1.m4a and input2.m4a.

```console
$ Get-Audio -InputFiles input1.mp4, input2.mp4 -Extension .m4a
```

Extract and splitting the audio stream from input.mp4 according to the track
informations in input.cue.

```console
$ Get-Audio -InputFiles input.mp4 -CueSheet input.cue
```

## Dependency

- `ffmpeg`
- `ffprobe`, used for splitting file.
