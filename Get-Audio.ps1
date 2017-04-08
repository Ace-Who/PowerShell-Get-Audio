# https://trac.ffmpeg.org/wiki/FFprobeTips

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true,Position=0,ValueFromRemainingArguments=$true)]
  [Array]$InputFiles,
  [String]$OutFile,
  [String]$OutDirectory,
  [String]$Extension,
  [String]$FFtoolLoglevel = 'info',
  # When $CueSheet is given, the input file will be splitted according to the
  # track informations in that file.
  [String]$CueSheet,
  [Switch]$FastProcess,
  [Switch]$KeepVideo,
  [Switch]$DryRun
)

''

if (($OutFile -ne '') -and (($OutDirectory -ne '') -or ($CueSheet -ne ''))) {
  Write-Error ('The "OutFile" option can''t be used together with' +
    ' "OutDirectory" or "CueSheet".')
  return
}

# Characters that are not allowed in file names
$nonIdentifierClass = '[\/:*?"<>|]'
$FFtoolLoglevels = @(
  'quiet'  , -8
  'panic'  ,  0
  'fatal'  ,  8
  'error'  , 16
  'warning', 24
  'info'   , 32
  'verbose', 40
  'debug'  , 48
  'trace'  , 56
)

if ($FFtoolLoglevels -cnotcontains $FFtoolLoglevel) {
  Write-Error "Invalid fftool loglevel '$FFtoolLoglevel'. Must be one of ($($FFtoolLoglevels -join ', '))."
  return
}

if (
  # Users may specify $InputFiles in the form of a comma seperated file list,
  # namely 'file1, file2, ...', in which case the whole array instead of the
  # strings indicating the files becomes the only item of $InputFiles. Then a
  # dimension reduction is needed.
  ($InputFiles.Count -eq 1) -and
  ($InputFiles[0].GetType().BaseType.Name -eq 'Array')
) { $InputFiles = $InputFiles[0] }

Function NotUsedPath ([String]$Path) {
  if (-not (Test-Path $Path)) { return $Path }
  $root = Split-Path $Path
  $leaf = Split-Path $Path -Leaf
  $lastDot = $leaf.LastIndexOf('.')
  if ($lastDot -eq -1) { $lastDot = $leaf.Length }
  $basename = $leaf.SubString(0, $lastDot)
  $ext = $leaf.SubString($lastDot)
  $i = 0
  do {
    $i++
    $newName = "$basename ($i)$ext"
    $newPath = "$root\$newName"
  } while (Test-Path $newPath)
  Write-Warning "File/Directory already exists. A new name will be used."
  return $newPath
}

Function Parse-Cuesheet ([String]$File, [String]$Duration) {
  $lines = Get-Content $File
  # A .Net ArrayList has the 'Add' method.
  # $tracks = New-Object System.Collections.ArrayList
  $tracks = @()
  # $fileLine = $lines -match '^ *file '
  foreach ($line in $lines) {
    $line = $line.Trim()
    if ($line -match '^track +(\d+)') {
      $track = New-Object -TypeName Object
      Add-Member -InputObject $track NoteProperty trackNr $Matches[1]
      $tracks += $track
      # $null = $tracks.Add($track)
    } elseif (($line -match '^title +(.+)') -and ($track -ne $null)) {
      Add-Member -InputObject $track NoteProperty title `
        $Matches[1].Replace('"', '')
    } elseif ($line -match '^index +01 +(.+)') {
      Add-Member -InputObject $track NoteProperty index $Matches[1]
      Add-Member -InputObject $track NoteProperty startTime `
        (CueIndex-to-Time $track.index)
      if ($tracks.count -ge 2) {
        $prevTrack = $tracks[$tracks.count - 2]
        Add-Member -InputObject $prevTrack NoteProperty endTime $track.startTime
        Add-Member -InputObject $prevTrack NoteProperty length `
          (New-TimeSpan $prevTrack.startTime $prevTrack.endTime)
      }
    }
  }
  # The last track
  Add-Member -InputObject $track NoteProperty endTime $Duration
  Add-Member -InputObject $track NoteProperty length `
    (New-TimeSpan $track.startTime $track.endTime)
  return $tracks
}

Function CueIndex-to-Time ([String]$Index) {
  $null = $Index -match '(\d+):(\d+):(\d+)';
  $min, $sec, $frame = $Matches[1..3];
  if (0 -ne $frame) {
    $ms = [Math]::Round($frame / 75, 3, [MidpointRounding]::AwayFromZero)
    $ms = '.' + "$ms".Split('.')[1]
  }
  $hr = [Math]::DivRem($min, 60, [ref]$min)
  Function pad0 ([String]$a) { $a.PadLeft(2, '0') }
  return "$(pad0 $hr):$(pad0 $min):$(pad0 $sec)$ms"
}

$FileCount = 0
foreach ($InputFile in $InputFiles) {

  # If $InputFiles is passed as the return value of a Get-ChildItem cmdlet
  # executed on a directory, as an folder item, when $InputFile is converted to
  # a string, which the Test-Path cmdlet and other commands do, not the full
  # path but only the file name is delivered, which may cause some commands
  # fail to find that file. 
  # That's the reason we need get its full path first.

  if ($InputFile.GetType().Name -eq 'FileInfo') {
    $InputFile = $InputFile.PSPath
  }

  $FileCount++
  Write-Host "In [$FileCount]: $InputFile" -ForegroundColor 'DarkGreen'

  if (-not (Test-Path $InputFile)) {
    Write-Error "File `"$InputFile`" not found."
    continue
  }

  $InputFile = Get-Item $InputFile
  $ParentFolder = Split-Path $InputFile

  if ($CueSheet -eq '') {

    if ($OutDirectory -eq '') { $OutDirectory = $ParentFolder }
    if ($OutFile -eq '') {
      if ($Extension -eq '') {
        if ($KeepVideo) { $Extension = $InputFile.Extension }
        else            { $Extension = '.m4a' }
      } elseif ($Extension[0] -ne '.') { $Extension = ".$Extension" }
      $OutFile = "$OutDirectory\$($InputFile.BaseName)$Extension"
    }

    $OutFile = NotUsedPath $OutFile

    Write-Host "Out[$FileCount]: $OutFile" -ForegroundColor 'DarkCyan'

    if ($DryRun) {
      if (-not (Test-Path $OutDirectory)) { mkdir $OutDirectory -WhatIf }
    } else {
      if (-not (Test-Path $OutDirectory)) { mkdir $OutDirectory }
      if ($KeepVideo) {
        ffmpeg -i $InputFile -c copy -loglevel $FFtoolLoglevel $OutFile
      } else {
        ffmpeg -i $InputFile -vn -c:a copy -loglevel $FFtoolLoglevel $OutFile
      }
    }

    $OutFile = ''; ''

  } else {

    if ($OutDirectory -eq '') {
      $OutDirectory = NotUsedPath "$ParentFolder\$($InputFile.BaseName)"
    }

    if ($Extension -eq '') {
      if ($KeepVideo) { $Extension = $InputFile.Extension }
      else            { $Extension = '.m4a' }
    } elseif ($Extension[0] -ne '.') { $Extension = ".$Extension" }

    if ($KeepVideo) {
      # Format (container) duration
      $duration = ffprobe -v error `
        -show_entries format=duration `
        -print_format default=noprint_wrappers=1:nokey=1 `
        -sexagesimal `
        $InputFile
    } else {
      # Stream (1st audio) duration
      $duration = ffprobe -v error -select_streams a:0 `
        -show_entries stream=duration `
        -print_format default=noprint_wrappers=1:nokey=1 `
        -sexagesimal `
        $InputFile
    }

    $tracks = Parse-Cuesheet $CueSheet $duration

    if ($DryRun) {
      if (-not (Test-Path $OutDirectory)) { mkdir $OutDirectory -WhatIf }
    } else {
      if (-not (Test-Path $OutDirectory)) { mkdir $OutDirectory }
    }

    foreach ($track in $tracks) {
      $title = $track.title -replace $nonIdentifierClass, ''
      $OutFile = "$OutDirectory\$($track.trackNr). $title$Extension"
      Add-Member -InputObject $track NoteProperty outFile $OutFile
      $track
      if ($DryRun) { continue }
      if ($KeepVideo) {
        ffmpeg -i $InputFile -map 0 -c:v copy -c:a copy -ss $track.startTime `
          -to $track.endTime -loglevel $FFtoolLoglevel $OutFile
      } elseif ($FastProcess) {
        # Faster but lack time accuracy on a video file with GOPs.
        ffmpeg -ss $track.startTime -i $InputFile -map 0 -vn -c:a copy `
          -to $track.length -loglevel $FFtoolLoglevel $OutFile
      } else {
        ffmpeg -i $InputFile -map 0 -vn -c:a copy -ss $track.startTime `
          -to $track.endTime -loglevel $FFtoolLoglevel $OutFile
      }
    }

  }
}
