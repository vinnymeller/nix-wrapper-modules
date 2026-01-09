{
  pkgs,
  self,
}:

let
  mpvWrapped =
    (self.wrappedModules.mpv.apply {
      inherit pkgs;
      scripts = [
        pkgs.mpvScripts.visualizer
      ];
      "mpv.conf".content = ''
        ao=null
        vo=null
      '';
    }).wrapper;

in
pkgs.runCommand "mpv-test" { } ''
  "${mpvWrapped}/bin/mpv" --version | grep -q "mpv"
  cat "${mpvWrapped.configuration.package}/bin/mpv" | grep -q "share/mpv/scripts/visualizer.lua"
  touch $out
''
