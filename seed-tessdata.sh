# Make Tesseract OCR language data available to Audiveris.
#
# This file is *sourced* by the audiveris wrapper, so that it can also export
# a fallback TESSDATA_PREFIX.
#
# Audiveris looks for its 'tessdata' folder in $TESSDATA_PREFIX first, and
# otherwise in its own (writable) config folder, which is also where its
# language manager downloads further languages into. So, unless the user has
# an opinion, we populate that config folder with the language files built by
# Nix: that keeps both offline OCR and the language manager working.
#
# Opt out with AUDIVERIS_NIX_SEED_TESSDATA=0, or point AUDIVERIS_NIX_TESSDATA
# at another folder of <lang>.traineddata files.

if [ "${AUDIVERIS_NIX_SEED_TESSDATA:-1}" != 0 ] && [ -z "${TESSDATA_PREFIX:-}" ]; then
    audiverisNixTessdata="${AUDIVERIS_NIX_TESSDATA:-@tessdata@}"
    audiverisNixConfig="${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/AudiverisLtd/audiveris"

    if @coreutils@/bin/mkdir -p "$audiverisNixConfig/tessdata" 2>/dev/null; then
        for audiverisNixLang in "$audiverisNixTessdata"/*.traineddata; do
            audiverisNixTarget="$audiverisNixConfig/tessdata/${audiverisNixLang##*/}"

            if [ -f "$audiverisNixLang" ] && [ ! -e "$audiverisNixTarget" ]; then
                # Copied rather than symlinked: a symlink into the Nix store
                # would dangle once this build is garbage collected.
                @coreutils@/bin/install -m644 \
                    "$audiverisNixLang" "$audiverisNixTarget" 2>/dev/null || true
            fi
        done
    else
        # No writable config folder (read-only HOME, sandbox, ...): fall back
        # to the read-only copy in the Nix store. Audiveris will then be
        # unable to install additional languages by itself.
        export TESSDATA_PREFIX="$audiverisNixTessdata"
    fi

    unset audiverisNixTessdata audiverisNixConfig audiverisNixLang audiverisNixTarget
fi
