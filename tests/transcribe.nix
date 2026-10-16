# Smoke test: transcribe one of the example scores shipped with Audiveris and
# check that MusicXML comes out. This also exercises the bundled JavaCPP
# Tesseract/Leptonica native libraries and the OCR language data.
{
  runCommand,
  audiveris,
  audiverisSrc,
}:

runCommand "audiveris-transcribe-test"
  {
    nativeBuildInputs = [ audiveris ];
  }
  ''
    export HOME="$PWD/home"
    mkdir -p "$HOME" out

    audiveris -batch -transcribe -export -output out \
      ${audiverisSrc}/data/examples/chula.png 2>&1 | tee log

    if [ -z "$(find out -name '*.mxl' -size +0 -print -quit)" ]; then
      echo "test failed: no MusicXML was exported" >&2
      find out >&2
      exit 1
    fi

    # The OCR engine must have come up: Audiveris only logs a warning and
    # carries on with text recognition disabled when it cannot load the
    # Tesseract natives or find any language data.
    if ! grep -q "Installed OCR languages" log \
      || grep -qE "No OCR (is )?available|Tesseract data could not be found|UnavailableOcr|Could not initialize TessBaseAPI" log; then
      echo "test failed: OCR did not initialize" >&2
      exit 1
    fi

    mkdir -p $out
    cp -r out log $out/
  ''
