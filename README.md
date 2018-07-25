# NeonSM
SourceMod Script for Neon

## Installation
NeonSM requires [REST in Pawn](https://forums.alliedmods.net/showthread.php?t=298024) and
[SMLIB](https://forums.alliedmods.net/showthread.php?t=148387)<sup>1</sup> to be installed.

1. [Download](https://github.com/neon-bot-project/NeonSM/releases) `neonsm.smx` and place it under the
`addons/sourcemod/plugins` directory. You may use any of the numerous checksum files to verify integrity.

2. Load the plugin using `sm plugins load neonsm`. You may safely ignore any errors during this step.

3. Find the `neonsm.cfg` configuration file and change the values accordingly. If you do not understand what values to
input refer to the documentation supplied by Neon.

4. Reload the plugin using `sm plugins reload neonsm`. There should be no errors during this step.

<sup>1</sup>NeonSM uses the `b4e8edb` commit version.
