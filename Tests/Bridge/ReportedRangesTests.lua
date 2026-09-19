local messages, moduleName = {}, 'develop'
local photo={localIdentifier=7}
local catalog={getTargetPhotos=function() return photo and {photo} or {} end,getTargetPhoto=function()return photo end,getPath=function()return '/test/Test.lrcat' end}
local modules={LrApplication={activeCatalog=function()return catalog end}, LrApplicationView={getCurrentModuleName=function()return moduleName end},LrPathUtils={leafName=function()return 'Test.lrcat' end,removeExtension=function()return 'Test' end},LrTasks={pcall=pcall}}
function import(name)return modules[name] or {} end
package.preload.serpent=function()return {} end
package.preload.Database=function()return {Parameters={Temperature={},Exposure={},Bad={}}} end
package.preload.Limits=function()return {GetMinMax=function(p) if p=='Temperature' then return 2000,50000 elseif p=='Exposure' then return -5,5 else error('unsupported') end end} end
MIDI2LR={SERVER={send=function(_,s)messages[#messages+1]=s end}}
local r=dofile('Packaging/PanaLux Bridge.lrplugin/PanaLuxRewind.lua')
r.PushSelection(); assert(#messages==3 and messages[1]=='PanaLuxSelection 1 Test:7 develop\n')
local joined=table.concat(messages);assert(joined:find('PanaLuxRange Test:7 Temperature 2000 50000',1,true))
r.PushSelection();assert(#messages==3,'unchanged selection must be quiet')
r.PushSelection(true);assert(#messages==6,'forced refresh must resend ranges')
moduleName='library';r.PushSelection();assert(#messages==7,'library should emit selection only')
photo=nil;r.PushSelection();assert(#messages==8,'empty selection should emit selection only')
print('PASS: selection order, numeric ranges, unsupported parameter isolation, deduplication, forced refresh, module and no-photo guards')
