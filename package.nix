{
  lib,
  stdenv,
  coreutils,
  runCommandLocal,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  gradle_9,
  gtk3,
  jdk25,
  tesseract,

  # Upstream sources, normally the 'audiveris' flake input.
  src,
  version ? "5.11.0-unstable",
  # Upstream commit, reported by Audiveris as its build id.
  rev ? null,

  # Tesseract OCR language data to ship. Audiveris needs at least "eng".
  # Any language of pkgs.tesseract.languages can be added, e.g.
  #   audiveris.override { tessdataLanguages = [ "eng" "deu" "jpn" ]; }
  tessdataLanguages ? [ "eng" ],
}:

let
  # Audiveris requires Java 25, which is also what gradle_9 runs on.
  # NOTE: deliberately not function arguments named 'jdk'/'gradle':
  # callPackage would fill those from nixpkgs (JDK 21 and Gradle 8).
  jdk = jdk25;
  gradle = gradle_9;

  commit = if rev != null then rev else "unknown";

  # A single directory holding <lang>.traineddata files, which is what
  # Tesseract expects TESSDATA_PREFIX to point at.
  tessdata = runCommandLocal "audiveris-tessdata" { } (
    ''
      mkdir -p $out
    ''
    + lib.concatMapStringsSep "\n" (
      lang: "cp ${tesseract.languages.${lang}} $out/${lang}.traineddata"
    ) tessdataLanguages
  );
in
stdenv.mkDerivation (finalAttrs: {
  pname = "audiveris";
  inherit version src;

  nativeBuildInputs = [
    gradle
    jdk
    makeWrapper
    copyDesktopItems
  ];

  mitmCache = gradle.fetchDeps {
    pkg = finalAttrs.finalPackage;
    data = ./deps.json;
  };

  postPatch = ''
    # Build only the application. The other subprojects package installers,
    # build the handbook or the flatpak, none of which applies here, and they
    # would drag in further build-time dependencies.
    cat > settings.gradle <<'EOF'
    pluginManagement {
      repositories {
        gradlePluginPortal()
      }
    }

    rootProject.name = 'Audiveris'

    include 'app'
    EOF

    # Audiveris stamps its build id with 'git log', but the source tree in the
    # sandbox is not a git repository. Report the commit we were given instead.
    substituteInPlace app/build.gradle \
      --replace-fail 'git log -n1 --pretty=%H -- :^../flatpak/flathub' 'echo ${commit}'
  '';

  gradleBuildTask = ":app:installDist";

  # The test suite needs a display and OCR language data.
  doCheck = false;

  installPhase = ''
    runHook preInstall

    # Gradle's start script finds the jars relative to its own location, so
    # bin/ and lib/ have to stay siblings.
    mkdir -p $out/share/audiveris
    cp -r app/build/install/*/{bin,lib} $out/share/audiveris/

    for size in 64 256; do
      install -Dm644 app/res/icon-$size.png \
        $out/share/icons/hicolor/''${size}x''${size}/apps/audiveris.png
    done

    substitute ${./seed-tessdata.sh} $out/share/audiveris/seed-tessdata.sh \
      --subst-var-by tessdata ${tessdata} \
      --subst-var-by coreutils ${coreutils}

    # Audiveris loads GTK 3 through JNA on startup to detect the display
    # scaling, and only catches Exception there, so a missing libgtk-3.so is
    # fatal. Tell JNA where to find it rather than putting a GUI toolkit on
    # LD_LIBRARY_PATH, which every child process would inherit.
    substituteInPlace $out/share/audiveris/bin/Audiveris \
      --replace-fail "DEFAULT_JVM_OPTS='" "DEFAULT_JVM_OPTS='\"-Djna.library.path=${gtk3}/lib\" "

    # JAVA_HOME is --set, not --set-default: Audiveris needs Java 25, and
    # environments such as CI runners often export a JAVA_HOME of their own.
    # LD_LIBRARY_PATH carries the C++ runtime for the Tesseract/Leptonica
    # libraries that the JavaCPP jars unpack at run time.
    makeWrapper $out/share/audiveris/bin/Audiveris $out/bin/audiveris \
      --set JAVA_HOME ${jdk} \
      --set-default AUDIVERIS_OPTS "-Xms512m -Xmx8g -Dfile.encoding=UTF-8" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ stdenv.cc.cc.lib ]} \
      --run ". $out/share/audiveris/seed-tessdata.sh"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "audiveris";
      exec = "audiveris %F";
      icon = "audiveris";
      desktopName = "Audiveris";
      genericName = "Optical Music Recognition";
      comment = "Transcribe sheet music images into MusicXML";
      categories = [
        "AudioVideo"
        "Audio"
        "Graphics"
      ];
      # Deliberately no mimeTypes: Audiveris reads PDFs and images, but it
      # should not advertise itself as a general viewer for them.
      startupWMClass = "Audiveris";
    })
  ];

  passthru = {
    inherit tessdata jdk;
  };

  meta = {
    description = "Optical Music Recognition engine, turning sheet music images into MusicXML";
    longDescription = ''
      Audiveris is an open-source Optical Music Recognition (OMR) application.
      It reads scanned or digital sheet music (images and PDFs) and transcribes
      it into MusicXML, which can then be edited in a score editor such as
      MuseScore or Finale.
    '';
    homepage = "https://audiveris.github.io/audiveris/";
    downloadPage = "https://github.com/Audiveris/audiveris/releases";
    changelog = "https://github.com/Audiveris/audiveris/releases";
    license = lib.licenses.agpl3Plus;
    mainProgram = "audiveris";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryBytecode # Maven dependencies, including JavaCPP native libraries
    ];
  };
})
