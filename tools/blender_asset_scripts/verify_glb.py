"""Inspect a .glb without Blender: nodes, materials, animations, bounds (metres, Y-up)."""
import json, struct, sys

def load(path):
    with open(path, 'rb') as f:
        magic, ver, length = struct.unpack('<4sII', f.read(12))
        clen, ctype = struct.unpack('<I4s', f.read(8))
        return json.loads(f.read(clen))

def main(path):
    g = load(path)
    print("file:", path)
    print("asset:", g.get('asset', {}).get('generator'), "| extensionsUsed:", g.get('extensionsUsed'))
    nodes = g['nodes']
    print("nodes:", len(nodes), "| meshes:", len(g.get('meshes', [])), "| materials:", [m['name'] for m in g.get('materials', [])])
    for i, n in enumerate(nodes):
        kids = [nodes[c]['name'] for c in n.get('children', [])]
        extra = {k: n[k] for k in ('translation', 'rotation', 'scale') if k in n}
        print(f"  {n['name']:<28} mesh={'y' if 'mesh' in n else '-'} children={kids} {extra}")
    for m in g.get('meshes', []):
        for p in m['primitives']:
            acc = g['accessors'][p['attributes']['POSITION']]
            print(f"  mesh {m['name']:<28} min={[round(x,3) for x in acc['min']]} max={[round(x,3) for x in acc['max']]} attrs={list(p['attributes'])}")
    for a in g.get('animations', []):
        chans = [(nodes[c['target']['node']]['name'], c['target']['path']) for c in a['channels']]
        print("animation:", a['name'], chans)

main(sys.argv[1])
