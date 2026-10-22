# Third-party notices

Hordes of Azeroth is licensed under the GNU General Public License v3.0 (see `LICENSE`). It builds on, ships with or downloads the following projects, each under its own licence.

Hordes of Azeroth is not affiliated with or endorsed by Blizzard Entertainment. It contains no Blizzard files: the launcher builds everything it needs from the player's own World of Warcraft 1.12.1 client on the player's PC.

| Project | Used for | Licence | Source |
| --- | --- | --- | --- |
| VMaNGOS | The game server (our fork: `server/core`) | GPL-2.0 | https://github.com/vmangos/core |
| VMaNGOS world database | The base of the shipped world database (`world-db`), with our changes applied | GPL-2.0 | https://github.com/vmangos/core/releases |
| ClassicAPI | Extra addon API in the client | GPL-3.0 | https://github.com/brues-code/ClassicAPI |
| MariaDB Server | The local database | GPL-2.0 | https://mariadb.org |
| vanilla-tweaks | Several of the client exe patches in `config/client-patches.json` | MIT | https://github.com/brndd/vanilla-tweaks |
| VanillaFixes | Client fixes and DLL loading | MIT | https://github.com/hannesmann/vanillafixes |
| wow_turbo | Faster client code for crowded fights (`mods/wow_turbo`, v1.13.3, AVX and SSE builds) | MIT | https://github.com/athei/wow-mods |
| Barlow Bold | Health numbers font in the addon (`Interface/AddOns/HordesOfAzeroth/Fonts`, licence in `Barlow-OFL.txt` beside it) | SIL Open Font License 1.1 | https://github.com/jpt/barlow |
| DXVK | Direct3D 9 to Vulkan (ships inside the VanillaFixes DXVK download) | zlib/libpng | https://github.com/doitsujin/dxvk |
| Microsoft Visual C++ Redistributable | Runtime DLLs next to the server and map tools | Microsoft Software License Terms (redistributable files) | https://learn.microsoft.com/cpp/windows/latest-supported-vc-redist |

MariaDB, VanillaFixes, DXVK and ClassicAPI are downloaded by the launcher from their own release pages; wow_turbo's release DLLs ship unchanged in our `wow-turbo` package; the VMaNGOS-based server is built from the fork's source, which is published alongside this repository.

## VanillaFixes

```
MIT License

Copyright (c) 2022 Hannes Mann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## DXVK

```
Copyright (c) 2017 Philip Rebohle
                  Copyright (c) 2019 Joshua Ashton
                  Copyright (c) 2019 Robin Kertels
                  Copyright (c) 2023 Jeffrey Ellison

                          zlib/libpng license

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

– The origin of this software must not be misrepresented; you must not
  claim that you wrote the original software. If you use this software
  in a product, an acknowledgment in the product documentation would be
  appreciated but is not required.

– Altered source versions must be plainly marked as such, and must not
  be misrepresented as being the original software.

– This notice may not be removed or altered from any source distribution.
```

## vanilla-tweaks

```
MIT License

Copyright (c) 2022 brndd

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## wow_turbo

```
MIT License

Copyright (c) 2026 Alexander Theißen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
# Co-op networking

The co-op edition includes Iroh 1.2.0 and its transitive Rust dependencies. Iroh is distributed under the MIT and Apache-2.0 licenses. The accompanying `HordesOfAzeroth-Rust-Licenses.zip` contains the dependency inventory and license notices from the locked Cargo dependency graph. The corresponding modified game sources accompany the edition as `HordesOfAzeroth-Coop-Sources.zip`.
