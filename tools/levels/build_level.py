#!/usr/bin/env python3
"""Pack, assemble, bake navigation and GI, then finalize a level JSON spec.

Usage: python tools/levels/build_level.py --spec tools/levels/out/l13/spec.json
Runs from the repository root; every engine call has an OS watchdog. Logs
are kept beside the spec. A failed bake stops the pipeline before finalizing.
The authored spec stays unchanged; spec.final.json records baked paths.
"""
from __future__ import annotations
import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def run(args: list[str], log: Path, timeout: int = 30) -> None:
    """Capture complete output and reject engine script failures even on exit0."""
    try:
        result = subprocess.run(args,cwd=ROOT,shell=False,capture_output=True,
                                text=True,timeout=timeout)
    except subprocess.TimeoutExpired as error:
        log.write_text(str(error))
        raise RuntimeError(f'Watchdog expired: {log}') from error
    output = result.stdout + result.stderr
    log.write_text(output,encoding='utf-8')
    if result.returncode or 'SCRIPT ERROR:' in output or 'ERROR: cannot' in output:
        raise RuntimeError(f'Build failed; inspect {log}')
    print(f'OK {log.name}',flush=True)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--spec',required=True,type=Path)
    args = ap.parse_args()
    spec_path = args.spec.resolve()
    spec = json.loads(spec_path.read_text())
    out = spec_path.parent
    engine = resolve_godot()
    prefix = [engine,'--path',str(ROOT)]
    # Files are engine resource paths; project-local paths use forward slashes.
    rel = lambda p: Path(p).resolve().relative_to(ROOT).as_posix()
    for number,(wall,target) in enumerate([(out/'wall.txt',spec['packed_cells'])] +
            [(out/'wall_upper.txt',layer['packed_cells']) for layer in spec.get('wall_layers',[])]):
        run(prefix+['--headless','-s','tools/levels/pack_cells.gd','--',
            '--floor='+rel(out/'floor.txt'),'--wall='+rel(wall),'--out='+target],out/f'pack{number}.log')
    working = out/'spec.final.json'
    working.write_text(json.dumps(spec,indent=2))
    assemble = [sys.executable,str(ROOT/'tools/levels/assemble_level.py'),'--spec',str(working)]
    run(assemble,out/'assemble.log')
    nav = out/'navmesh_baked.txt'
    run(prefix+['--headless','tools/levels/bake_navmesh_scene.tscn','--',
        '--level='+spec['out'],'--out='+rel(nav)],out/'navmesh.log',60)
    spec['navmesh_snippet'] = rel(nav)
    working.write_text(json.dumps(spec,indent=2))
    run(assemble,out/'assemble_nav.log')
    gi = 'Levels/GlobalIlluminationData/'+Path(spec['out']).stem+'_voxel_gi_data.res'
    run(prefix+['tools/levels/bake_level_gi.tscn','--','--level='+spec['out'],
        '--gi-out='+gi],out/'gi.log',120)
    assert (ROOT/gi).is_file(), 'GI bake did not produce data'
    spec['gi_data'] = 'res://'+gi
    working.write_text(json.dumps(spec,indent=2))
    run(assemble,out/'assemble_final.log')
    print('Finished '+spec['out'],flush=True)


if __name__ == '__main__':
    main()
