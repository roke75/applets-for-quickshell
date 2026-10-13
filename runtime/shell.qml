import Quickshell
import qs.Applets

// Standalone runtime for setups without their own Quickshell config.
// Started by `qsa daemon`. To embed applets in an existing shell instead,
// see `qsa setup` in the README.
ShellRoot {
    AppletsHost {}
}
