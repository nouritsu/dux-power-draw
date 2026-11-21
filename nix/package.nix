{
  lib,
  stdenvNoCC,
  writeShellApplication,
  writeShellScript,
  coreutils,
  pciutils,
  upower,
  glib,
}: let
  # one json line a second: rapl counters, cpu rail and temperature, clocks,
  # cpu time, battery voltage and conservation mode
  sampler = writeShellApplication {
    name = "dux-power-draw-sampler";
    runtimeInputs = [coreutils pciutils];
    text = builtins.readFile ../scripts/sampler.sh;
  };

  # upower's charge history for the laptop battery
  history = writeShellApplication {
    name = "dux-power-draw-history";
    runtimeInputs = [upower glib];
    text = ''
      device=""
      while read -r path; do
        case $path in
          */battery_*)
            device=$path
            break
            ;;
        esac
      done < <(upower -e)
      [ -n "$device" ] || exit 1
      gdbus call --system --dest org.freedesktop.UPower --object-path "$device" \
        --method org.freedesktop.UPower.Device.GetHistory charge 86400 288
    '';
  };

  # writes 0 or 1 and nothing else; a polkit rule can name it
  conservation = writeShellScript "dux-power-draw-conservation" ''
    [[ $1 == [01] ]] || exit 2
    echo "$1" > /sys/bus/platform/devices/VPC2004:00/conservation_mode
  '';
in
  stdenvNoCC.mkDerivation {
    pname = "dux-power-draw";
    inherit (lib.importJSON ../plugin/plugin.json) version;

    src = ../plugin;

    installPhase = ''
      runHook preInstall
      cp -r . $out
      substituteInPlace $out/PowerDrawDaemon.qml \
        --replace-fail @sampler@ ${lib.getExe sampler} \
        --replace-fail @history@ ${lib.getExe history} \
        --replace-fail @conservation@ ${conservation}
      runHook postInstall
    '';

    passthru = {inherit conservation;};
  }
