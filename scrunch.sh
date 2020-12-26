#!/usr/bin/env bash
FFMPEG=/usr/local/bin/ffmpeg
GM=/usr/local/bin/gm
PNGQUANT=/usr/local/bin/pngquant
SIPS=/usr/bin/sips
ZOPFLIPNG=/usr/local/bin/zopflipng

PNG_MAX_COLORS=64

function is_uncompressed_png {
  declare -r source_file=${1:?"A source PNG file must be specified."}

  number_colors=$($GM identify -format '%k' "$source_file")
  ! [ ! "$number_colors" -gt "$PNG_MAX_COLORS" ] || return 1
}

function auto_orient {
  declare -r source_file=${1:?"A source file must be specified."}
  declare -r target_file=${2:?"A target file must be specified."}

  # HACK: Orientation using EXIF metadata is not compatible with all browsers
  $GM convert -auto-orient "$source_file" "$target_file" || return $?
}

function quantize_png {
  declare -r source_file=${1:?"A source PNG file must be specified."}
  declare -r target_file=${2:?"A target PNG file must be specified."}

  # Quantize to PNG-8 with 64 colors (lossy, fast)
  # Majority of filesize savings come from this
  $PNGQUANT $PNG_MAX_COLORS --skip-if-larger --strip --force --output="$target_file" "$source_file" || return $?
}

function deflate_png {
  declare -r source_file=${1:?"A source PNG file must be specified."}
  declare -r target_file=${2:?"A target PNG file must be specified."}

  # Zopfli improves PNG compression by approximately 10%
  $ZOPFLIPNG -y "$source_file" "$target_file" || return $?
}

function mov_to_mp4 {
  declare -r source_file=${1:?"A source MOV file must be specified."}
  declare -r target_file=${2:?"A target MP4 file must be specified."}

  $FFMPEG -i "$source_file" -vcodec h264 -acodec mp2 -f mp4 "$target_file" || return $?
}

function heic_to_jpeg {
  declare -r source_file=${1:?"A source HEIC file must be specified."}
  declare -r target_file=${2:?"A target JPEG file must be specified."}

  $SIPS -s format jpeg "$source_file" --out "$target_file" || return $?
}

function to_webp {
  declare -r source_file=${1:?"A source file must be specified."}
  declare -r target_file=${2:?"A target WebP file must be specified."}

  $GM convert -format webp "$source_file" "$target_file" || return $?

}

function to_lossless_webp {
  declare -r source_file=${1:?"A source PNG file must be specified."}
  declare -r target_file=${2:?"A target file must be specified."}

  $GM convert -format webp -define webp:lossless=true "$source_file" "$target_file" || return $?
}

function process_file {
  declare -r source_file=${1:?"A source file must be specified."}

  target_file="$(dirname "$source_file")/$(date -r "$source_file" +"%Y-%m-%dT%H.%M.%S")"

  mime_type=$(file --brief --mime-type "$source_file")
  case "$mime_type" in
    image/png)
      is_uncompressed_png "$source_file" || return

      temp_target=$(mktemp)
      png_target=$target_file.png
      webp_target=$target_file.webp

      quantize_png "$source_file" "$temp_target" || return
      to_lossless_webp "$temp_target" "$webp_target" || continue
      deflate_png "$temp_target" "$png_target" || return

      rm "$temp_target"
      ;;
    image/heic)
      temp_target=$(mktemp)
      jpeg_target=$target_file.jpg
      webp_target=$target_file.webp

      heic_to_jpeg "$source_file" "$temp_target" || return
      auto_orient "$temp_target" "$jpeg_target" || return
      to_webp "$jpeg_target" "$webp_target" || return

      rm "$temp_target"
      ;;
    video/quicktime)
      mov_to_mp4 "$source_file" "$target_file.mp4"
      ;;
    *) return ;;
  esac

  if [ $? -eq 0 ]; then
    rm "$source_file"

    # Copy to clipboard (optional)
    # osascript -e "set the clipboard to (read (POSIX file \"$(perl -e "print glob('$new_file')")\") as {«class PNGf»})"
  fi
}

for source_file in "$@"
do
  process_file "$source_file"
done
