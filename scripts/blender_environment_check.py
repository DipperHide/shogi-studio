import bpy
from pathlib import Path
root=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(root/'models/shogi-scene.glb'))
meshes=[o for o in bpy.data.objects if o.type=='MESH']
assert len(meshes)>=40
bpy.ops.wm.save_as_mainfile(filepath=str(root/'models/shogi-scene.blend'))
print('BLENDER_ENVIRONMENT_CHECK_OK: imported',len(meshes),'meshes; editable blend saved')
