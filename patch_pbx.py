import re
import sys

pbx_path = 'MusicVideoMacApp.xcodeproj/project.pbxproj'
with open(pbx_path, 'r') as f:
    content = f.read()

id_file = 'B05F8077C1F94248AC122D2D'
id_build = '989F3BA193644CED8E6F19E6'
filename = 'ImageCropperView.swift'

# 1. PBXBuildFile section
content = re.sub(
    r'(/\* Begin PBXBuildFile section \*/\n)',
    f'\\1\t\t{id_build} /* {filename} in Sources */ = {{isa = PBXBuildFile; fileRef = {id_file} /* {filename} */; }};\n',
    content
)

# 2. PBXFileReference section
content = re.sub(
    r'(/\* Begin PBXFileReference section \*/\n)',
    f'\\1\t\t{id_file} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {filename}; sourceTree = "<group>"; }};\n',
    content
)

# 3. Add to Components group (where NumericSlider is)
# Let's find the group that contains NumericSlider.swift
group_match = re.search(r'children = \(\n[^\)]*?NumericSlider\.swift.*?\n\t\t\t\);', content, re.DOTALL)
if group_match:
    group_str = group_match.group(0)
    new_group_str = group_str.replace('\t\t\t);', f'\t\t\t\t{id_file} /* {filename} */,\n\t\t\t);')
    content = content.replace(group_str, new_group_str)
else:
    print("Could not find NumericSlider group")
    sys.exit(1)

# 4. Add to PBXSourcesBuildPhase
sources_match = re.search(r'isa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = .*?;\n\t\t\tfiles = \(\n[^\)]*?\t\t\t\);', content, re.DOTALL)
if sources_match:
    sources_str = sources_match.group(0)
    new_sources_str = sources_str.replace('\t\t\t);', f'\t\t\t\t{id_build} /* {filename} in Sources */,\n\t\t\t);')
    content = content.replace(sources_str, new_sources_str)
else:
    print("Could not find PBXSourcesBuildPhase")
    sys.exit(1)

with open(pbx_path, 'w') as f:
    f.write(content)

print("Patched successfully")
