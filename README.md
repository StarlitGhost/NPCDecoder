# NPCDecoder

A Windower 4 addon that decodes model data in non-precomposed NPC update packets.

Outputs:
- AltanaView PC gear inis
- Noesis DAT sets

The rest of the json files you'll need to use this are available from [MurphyCodes/FFXI_DATS](https://github.com/MurphyCodes/FFXI_DATS/tree/main/Race%20specific%20model.DATS), download that repo and copy the folders under `Race specific model.DATS` into `json/`

A lot of NPCs need to be encountered twice to actually send model data, so you'll need to do two passes of most zones to pick up everything.

I also haven't mapped out child faces/outfits or chocobos yet, so those won't load correctly. The output files generated for those contain the unmapped model IDs instead.
