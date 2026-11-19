#!/usr/bin/env python3
"""Generate an Xcode app project without an Apple account or external packages."""
from pathlib import Path
import json
root=Path(__file__).resolve().parents[1]
objects={}; counter=0
def add(isa,**attrs):
 global counter
 counter+=1; key=f'{counter:024X}'; objects[key]=dict(isa=isa,**attrs); return key
def ref(path,kind):return add('PBXFileReference',lastKnownFileType=kind,path=path,sourceTree='<group>')
files=[ref('Sources/'+p.name,'sourcecode.swift') for p in sorted((root/'Sources').glob('*.swift'))]
shared=[ref('Shared/'+p.name,'sourcecode.swift') for p in sorted((root/'Shared').glob('*.swift'))]
helper_source=ref('Helper/main.swift','sourcecode.swift')
helper_product=add('PBXFileReference',explicitFileType='compiled.mach-o.executable',path='AwakeLiteLidHelper',sourceTree='BUILT_PRODUCTS_DIR')
icon=ref('Resources/AppIcon.icns','image.icns')
product=add('PBXFileReference',explicitFileType='wrapper.application',path='AwakeLite.app',sourceTree='BUILT_PRODUCTS_DIR')
products=add('PBXGroup',children=[product,helper_product],name='Products',sourceTree='<group>')
group=add('PBXGroup',children=files+shared+[helper_source,icon,products],sourceTree='<group>')
settings=dict(SDKROOT='macosx',MACOSX_DEPLOYMENT_TARGET='26.0',SWIFT_VERSION='5.0',PRODUCT_NAME='AwakeLite',PRODUCT_BUNDLE_IDENTIFIER='org.awakelite.app',GENERATE_INFOPLIST_FILE='NO',INFOPLIST_FILE='Resources/Info.plist',CODE_SIGN_IDENTITY='-',CODE_SIGN_STYLE='Manual',ENABLE_HARDENED_RUNTIME='YES',CODE_SIGN_INJECT_BASE_ENTITLEMENTS='NO',SWIFT_STRICT_CONCURRENCY='targeted',ONLY_ACTIVE_ARCH='NO',ARCHS='$(ARCHS_STANDARD)',MARKETING_VERSION='0.2.0',CURRENT_PROJECT_VERSION='2',ENABLE_USER_SCRIPT_SANDBOXING='NO')
def configs(overrides=None):
 config_settings = dict(settings, **(overrides or {}))
 configs=[add('XCBuildConfiguration',name=n,buildSettings=dict(config_settings,SWIFT_OPTIMIZATION_LEVEL='-O' if n=='Release' else '-Onone')) for n in ['Debug','Release']]
 return add('XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
def source_phase(refs):
 return add('PBXSourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=f) for f in refs],runOnlyForDeploymentPostprocessing=0)
sources=source_phase(files+shared)
helper=add('PBXNativeTarget',buildConfigurationList=configs(dict(PRODUCT_NAME='AwakeLiteLidHelper',PRODUCT_BUNDLE_IDENTIFIER='org.awakelite.app.LidHelper',GENERATE_INFOPLIST_FILE='YES',INFOPLIST_FILE='',CREATE_INFOPLIST_SECTION_IN_BINARY='YES',SKIP_INSTALL='YES')),buildPhases=[source_phase([helper_source]+shared)],buildRules=[],dependencies=[],name='AwakeLiteLidHelper',productName='AwakeLiteLidHelper',productReference=helper_product,productType='com.apple.product-type.tool')
embed=add('PBXShellScriptBuildPhase',buildActionMask=2147483647,files=[],inputPaths=['$(BUILT_PRODUCTS_DIR)/AwakeLiteLidHelper','$(SRCROOT)/Resources/org.awakelite.app.LidHelper.plist'],outputPaths=['$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/MacOS/AwakeLiteLidHelper','$(TARGET_BUILD_DIR)/$(CONTENTS_FOLDER_PATH)/Library/LaunchDaemons/org.awakelite.app.LidHelper.plist'],runOnlyForDeploymentPostprocessing=0,shellPath='/bin/sh',shellScript='set -eu\nmkdir -p "$(dirname "$SCRIPT_OUTPUT_FILE_0")" "$(dirname "$SCRIPT_OUTPUT_FILE_1")"\n/usr/bin/ditto "$SCRIPT_INPUT_FILE_0" "$SCRIPT_OUTPUT_FILE_0"\n/bin/cp "$SCRIPT_INPUT_FILE_1" "$SCRIPT_OUTPUT_FILE_1"\n',name='Embed signed helper')

resources=add('PBXResourcesBuildPhase',buildActionMask=2147483647,files=[add('PBXBuildFile',fileRef=icon)],runOnlyForDeploymentPostprocessing=0)
target=add('PBXNativeTarget',buildConfigurationList=configs(),buildPhases=[sources,resources,embed],buildRules=[],dependencies=[add('PBXTargetDependency',target=helper)],name='AwakeLite',productName='AwakeLite',productReference=product,productType='com.apple.product-type.application')
project=add('PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES'},buildConfigurationList=configs(),compatibilityVersion='Xcode 14.0',developmentRegion='zh-Hans',hasScannedForEncodings=0,knownRegions=['zh-Hans','en','Base'],mainGroup=group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[target,helper])
def val(x):
 if isinstance(x,dict):return '{\n'+''.join(json.dumps(k)+' = '+val(v)+';\n' for k,v in x.items())+'}'
 if isinstance(x,list):return '('+','.join(val(v) for v in x)+')'
 if isinstance(x,int):return str(x)
 return json.dumps(x,ensure_ascii=False)
p=root/'AwakeLite.xcodeproj'/'project.pbxproj';p.parent.mkdir(exist_ok=True)
p.write_text('// !$*UTF8*$!\n'+val(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project))+'\n')
print(p)
