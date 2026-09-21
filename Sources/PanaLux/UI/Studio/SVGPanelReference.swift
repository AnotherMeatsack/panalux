import Foundation

/// Read-only panels built from the same SVG and semantic IDs as the mapper.
struct ReferencePanelState {
    let title: String
    let context: String
    let profile: Profile
    var emphasized: Set<String> = []
}

enum SVGPanelReference {
    static let esc = PanelReference.escape
    static let asset = AppResources.string("micro-color-panel", "svg") ?? "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 1080 552'></svg>"

    static func overlay(_ name: String, bank: String?, on base: Profile, engine: StudioEngine) -> Profile {
        guard let layer = engine.profile.layers[name] else { return base }
        var p = base
        if name == "MASK" { p.knobs = [:]; p.rings = [:]; p.balls = [:] }
        p.knobs.merge(engine.knobsForLayer(name, variant: bank) ?? [:]) { _, b in b }
        p.rings.merge(layer.rings ?? [:]) { _, b in b }
        p.balls.merge(layer.balls ?? [:]) { _, b in b }
        for (id, var b) in layer.buttons ?? [:] {
            if !b.hasHoldFunctionSet, let prior = p.buttons[id] {
                b.hold_layer = prior.hold_layer; b.holdProgram = prior.holdProgram
                b.hold_action = prior.hold_action; b.release_action = prior.release_action
                b.hold_picker = prior.hold_picker; b.modifier = prior.modifier
            }
            p.buttons[id] = b
        }
        if name == "REWIND" {
            p.knobs = p.knobs.filter { RewindCommands.isRewind($0.value.param) }
            p.rings = p.rings.filter { RewindCommands.isRewind($0.value.param) }
            p.balls = [:]
        }
        return p
    }

    static func applying(_ program: AnalogProgram, to source: Profile, engine: StudioEngine) -> Profile {
        var p = source
        if program.scope == "focus", let raw = program.focusParam, !raw.isEmpty {
            let param = engine.resolveProgramParam(raw)
            if program.appliesToKnobs { for id in PanelLayout.knobs { p.knobs[id] = KnobBinding(param: param) } }
            if program.appliesToWheels {
                for id in PanelLayout.rings { p.rings[id] = RingBinding(param: param) }
                for id in PanelLayout.balls { p.balls[id] = .slider(param) }
            }
        } else {
            if program.appliesToKnobs { p.knobs.merge(program.knobs ?? [:]) { _, b in b } }
            if program.appliesToWheels {
                p.rings.merge(program.rings ?? [:]) { _, b in b }
                p.balls.merge(program.balls ?? [:]) { _, b in b }
            }
        }
        return p
    }

    static func states(for engine: StudioEngine) -> [ReferencePanelState] {
        let base = engine.profile
        var states = [ReferencePanelState(title: "Live · Current controls", context: engine.referenceContext, profile: engine.currentHelpProfile()),
                      ReferencePanelState(title: "Base", context: "Your current map · no active mode", profile: base)]
        for (id, layer) in base.layers.sorted(by: { engine.layerTitle($0.key) < engine.layerTitle($1.key) }) {
            let banks: [String?] = (layer.variants?.isEmpty == false) ? layer.variants!.keys.sorted().map { Optional($0) } : [nil]
            let owners = base.buttons.sorted(by: { $0.key < $1.key }).compactMap { key, binding -> String? in
                if binding.hold_layer == id { return "Hold " + PanelLayout.label(forControl: key) }
                if binding.layer == id { return "Tap " + PanelLayout.label(forControl: key) }
                if binding.enter_layer == id { return PanelLayout.label(forControl: key) + " enters mode" }
                return nil
            }
            for bank in banks {
                let title = engine.layerTitle(id) + (bank.map { " · " + $0 } ?? "")
                let context = (owners.isEmpty ? "Assign this mode in Map" : owners.joined(separator: " / ")) + "; combinations take priority."
                states.append(.init(title: title, context: context, profile: overlay(id, bank: bank, on: base, engine: engine)))
            }
        }
        // Include actual custom analog programs, rather than just their summary names.
        let programSources = [("Base", base, base.buttons)] + base.layers.keys.sorted().map {
            (engine.layerTitle($0), overlay($0, bank: base.layers[$0]?.default_variant, on: base, engine: engine), base.layers[$0]?.buttons ?? [:])
        }
        for (sourceName, source, bindings) in programSources {
            for (key, binding) in bindings.sorted(by: { $0.key < $1.key }) {
                for (gesture, program) in [("Tap", binding.tapProgram), ("Hold", binding.holdProgram)] {
                    guard let program else { continue }
                    states.append(.init(title: "\(sourceName) · \(gesture) \(PanelLayout.label(forControl: key))", context: "Custom program · " + program.summary,
                                        profile: applying(program, to: source, engine: engine), emphasized: [key]))
                }
            }
        }
        let groups = Dictionary(grouping: base.combinations ?? ButtonCombination.defaults) { Set($0.held).sorted().joined(separator: "+") }
        for key in groups.keys.sorted() {
            let entries = groups[key]!
            let held = entries[0].held.sorted()
            var p = base
            let layers = Set(held.compactMap { base.buttons[$0]?.hold_layer }).sorted()
            for layer in layers.reversed() { p = overlay(layer, bank: base.layers[layer]?.default_variant, on: p, engine: engine) }
            for entry in entries { p.buttons[entry.trigger] = entry.binding }
            states.append(.init(title: "Combinations · " + held.map { PanelLayout.label(forControl: $0) }.joined(separator: " + "), context: "Button combinations · Hold the outlined keys, then press a mapped target. Combination actions take priority.", profile: p, emphasized: Set(held + entries.map(\.trigger))))
        }
        return states
    }

    private static func wrapped(_ text: String, columns: Int) -> [String] {
        var lines: [String] = [], current = ""
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            var part = String(word)
            if !current.isEmpty && current.count + part.count + 1 > columns { lines.append(current); current = "" }
            while part.count > columns {
                if !current.isEmpty { lines.append(current); current = "" }
                lines.append(String(part.prefix(columns))); part = String(part.dropFirst(columns))
            }
            if !part.isEmpty { current += (current.isEmpty ? "" : " ") + part }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? ["—"] : lines
    }

    struct Drawing { let svg: String; let fullLabels: [(String, String)] }

    static func drawing(_ state: ReferencePanelState, holds: Bool) -> Drawing {
        guard let doc = try? XMLDocument(xmlString: asset, options: []), let root = doc.rootElement() else { return Drawing(svg: asset, fullLabels: []) }
        let rows = Dictionary(ControlHelpRow.rows(profile: state.profile).filter { !$0.id.hasPrefix("combination:") }.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let controls = (try? root.nodes(forXPath: ".//*[@data-control-id]")) ?? []
        // The mapper's original interactive roles are not reference actions. Keep its
        // geometry while exposing only the assignment cards to keyboard/VoiceOver.
        if let group = (try? root.nodes(forXPath: ".//*[@id='controls']").first) as? XMLElement {
            group.addAttribute(XMLNode.attribute(withName: "aria-hidden", stringValue: "true") as! XMLNode)
        }
        for case let node as XMLElement in controls { node.removeAttribute(forName: "tabindex"); node.removeAttribute(forName: "role") }
        var annotations = "", fullLabels: [(String, String)] = []
        for case let node as XMLElement in controls {
            guard let svgID = node.attribute(forName: "data-control-id")?.stringValue, let id = PanelControlMapping.svgToProfile[svgID], let row = rows[id] else { continue }
            let knob = PanelLayout.isKnob(id), ball = PanelLayout.isBall(id), ring = PanelLayout.isRing(id)
            let press = rows["PRESS_" + id]
            let knobPress = (press?.action ?? "Reset current parameter") + ((press?.hold.isEmpty == false) ? " · Hold: " + press!.hold : "")
            var action = knob && holds ? knobPress : (!knob && !ball && !ring && holds ? (row.hold.isEmpty ? "No hold" : row.hold) : row.action)
            if holds && ["PREV_STILL", "NEXT_STILL"].contains(id) {
                action = (action == "No hold" ? "" : action + " · ") + "Together: Panel guide"
            }
            let physical = PanelLayout.shortLabel(forControl: id)
            var x = 0.0, y = 0.0, w = 53.0, h = 38.0, font = 7.1, linesMax = 3
            if knob {
                let face = (try? node.nodes(forXPath: ".//*[@id='\(svgID)-face']").first) as? XMLElement
                let cx = Double(face?.attribute(forName: "cx")?.stringValue ?? "0") ?? 0
                x = cx - 37; y = 27; w = 74; h = 65; font = 7.3; linesMax = 5
                annotations += "<path d='M \(cx) 92 V 107' stroke='#18818c' stroke-width='1.2'/>"
            } else if ball || ring {
                // Centres come from the original SVG; rings share the matching trackball centre.
                let targetID = ring ? svgID.replacingOccurrences(of: "ring_", with: "trackball_") : svgID
                let face = (try? root.nodes(forXPath: ".//*[@id='\(targetID)-face']").first) as? XMLElement
                let cx = Double(face?.attribute(forName: "cx")?.stringValue ?? "0") ?? 0
                x = cx - (ball ? 45 : 88); y = ball ? 354 : 491; w = ball ? 90 : 176; h = ball ? 62 : 36
                font = ball ? 8 : 7.5; linesMax = ball ? 5 : 2
                if ring { annotations += "<path d='M \(cx) 478 V 491' stroke='#18818c' stroke-width='1.2'/>" }
            } else {
                let face = (try? node.nodes(forXPath: ".//*[@class='interactive-face']").first) as? XMLElement
                x = (Double(face?.attribute(forName: "x")?.stringValue ?? "0") ?? 0) - 2
                y = (Double(face?.attribute(forName: "y")?.stringValue ?? "0") ?? 0) - 2
                w = (Double(face?.attribute(forName: "width")?.stringValue ?? "49") ?? 49) + 4
                // Clear original button text; the exact physical name is retained on the card.
                for text in (try? node.nodes(forXPath: ".//*[local-name()='text']")) ?? [] { text.detach() }
            }
            let lines = wrapped(action, columns: max(8, Int((w - 6) / (font * 0.54))))
            let shortened = lines.count > linesMax
            if shortened { fullLabels.append((physical, action)) }
            let stroke = state.emphasized.contains(id) ? "#d06412" : "#739aa4"
            let attrs = "data-ref='\(esc(id))' data-name='\(esc(row.control))' data-turn='\(esc(row.action))' data-press='\(esc(press?.action ?? ""))' data-hold='\(esc(knob ? (press?.hold ?? "") : row.hold))'"
            annotations += "<g \(attrs) role='button' tabindex='0' aria-label='\(esc(physical + ": " + action))'><title>\(esc(physical + ": " + action))</title><rect x='\(x)' y='\(y)' width='\(w)' height='\(h)' rx='3' fill='white' stroke='\(stroke)' stroke-width='\(state.emphasized.contains(id) ? 2 : 0.6)'/>"
            let titleFont = ball || ring || knob ? 6.1 : 4.6
            annotations += "<text x='\(x + w / 2)' y='\(y + 7)' text-anchor='middle' font-size='\(titleFont)' font-weight='700' fill='#42616b'>\(esc(physical))</text>"
            for (i, line) in lines.prefix(linesMax).enumerated() {
                let text = shortened && i == linesMax - 1 ? String(line.dropLast(min(2, line.count))) + "…*" : line
                annotations += "<text x='\(x + w / 2)' y='\(y + 16 + Double(i) * (font + 0.7))' text-anchor='middle' font-size='\(font)' fill='#122b34'>\(esc(text))</text>"
            }
            annotations += "</g>"
        }
        // Keep all real geometry, but use a low-ink chassis and brighter control faces.
        let style = "<style>#chassis-outline{fill:#e8edf1;stroke:#8b9da7}#chassis-inner-edge{stroke:#c5d0d6}#top-recess-surround,#top-recess,#top-recess-lip{opacity:0}.control-encoder .interactive-face{fill:#5c7480}.control-ring .interactive-face{fill:#c2cdd4;stroke:#8296a3}.control-trackball .interactive-face{fill:#f8fafb;stroke:#839aa7}[id^=socket_] circle{fill:#e8edf1;stroke:#9fb0ba}.control-encoder .control-label{fill:#25434d}text{font-family:Arial,Helvetica,sans-serif}[data-ref]{cursor:pointer}[data-ref]:hover rect,[data-ref]:focus rect{stroke:#d06412;stroke-width:1.8}</style>"
        let svg = root.xmlString.replacingOccurrences(of: "</svg>", with: style + annotations + "</svg>")
        return Drawing(svg: svg, fullLabels: fullLabels)
    }

    static func sheet(_ state: ReferencePanelState, holds: Bool) -> String {
        let drawn = drawing(state, holds: holds)
        let gesture = holds ? "Press / Hold" : "Turn / Tap"
        let detail = drawn.fullLabels.isEmpty ? "" : "<div class=full-labels><b>* Full assignments</b>" + drawn.fullLabels.map { "<p><strong>\(esc($0.0)):</strong> \(esc($0.1))</p>" }.joined() + "</div>"
        return "<article class='diagram \(holds ? "holds" : "taps")'><h2>\(esc(state.title)) <span>\(gesture)</span></h2><p class=context>\(esc(state.context))</p><div class=svg-wrap>\(drawn.svg)</div>\(detail)<p class=legend>\(holds ? "Knobs show PRESS; buttons show HOLD. Wheel assignments remain visible." : "Knobs and wheels show TURN / ROLL; buttons show TAP.") Orange outlines identify a combination or program. * Full labels appear below. Hold Previous Still + Next Still for this guide. Use region zoom for larger labels.</p></article>"
    }

    static func document(states: [ReferencePanelState], peek: Bool = false, atlas: Bool = false) -> String {
        let options = states.enumerated().map { "<option value='\($0.offset)'>\(esc($0.element.title))</option>" }.joined()
        let pages = states.enumerated().map { index, state in "<section class='state\(index == 0 ? " selected" : "")' data-index='\(index)'>" + sheet(state, holds: false) + sheet(state, holds: true) + "</section>" }.joined()
        return """
        <!doctype html><html><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'><title>PanaLux · Panel Reference</title><style>
        *{box-sizing:border-box}body{margin:0;background:#eef2f5;color:#18333e;font:14px -apple-system,Arial,sans-serif}button,select{font:inherit;padding:8px 11px;border:1px solid #a8bbc5;border-radius:7px;background:white;color:#16333e;cursor:pointer}button.active{background:#163f4d;color:white}.toolbar{position:sticky;top:0;z-index:3;background:#f8fafbf5;padding:12px 18px;border-bottom:1px solid #c4d0d7;display:flex;gap:8px;flex-wrap:wrap;align-items:center}.toolbar strong{margin-right:8px}.toolbar label{display:flex;align-items:center;gap:6px}.toolbar select{max-width:300px}.tools{display:flex;gap:6px;flex-wrap:wrap}.hint{padding:8px 20px;margin:0;font-size:12px;color:#435f6a}.state{display:none}.state.selected{display:block}.diagram{background:white;margin:12px;padding:14px;border-radius:12px;border:1px solid #cfdae0;break-after:page}.diagram h2{font-size:20px;margin:0 0 4px}.diagram h2 span{font-size:14px;color:#147e8b;margin-left:14px}.context{font-size:12px;margin:0 0 6px}.svg-wrap svg{overflow:hidden;margin:auto;display:block;width:100%;height:auto;aspect-ratio:1080/552}.diagram.holds{display:none}body[data-gesture=holds] .diagram.taps{display:none}body[data-gesture=holds] .diagram.holds,body[data-gesture=both] .diagram.holds{display:block}.legend{font-size:11px;color:#536a74;margin:5px 0 0}.full-labels{font-size:12px;columns:2;margin:8px 0}.full-labels p{margin:3px 0;break-inside:avoid}.inspector{margin:12px;padding:13px 18px;background:#163f4d;color:white;border-radius:10px;position:sticky;bottom:8px;display:flex;gap:20px;flex-wrap:wrap}.inspector span{white-space:pre-wrap}.atlas main{display:grid;grid-template-columns:repeat(2,minmax(0,1fr))}.atlas .state{display:block}.atlas .diagram h2{font-size:15px}.atlas .diagram{margin:6px;padding:10px}.atlas .legend{display:none}#printdetails{display:none}.peek .print-tools{display:none}.peek .hint{font-size:11px}.peek .toolbar{padding:8px}.peek .diagram{margin:5px;padding:8px}.peek .diagram h2{font-size:16px}.peek .inspector{font-size:12px;margin:5px;padding:8px}.peek .legend{font-size:9px}
        @page{size:A3 landscape;margin:10mm}@media print{body{background:white;font-size:11px}.toolbar,.hint,.inspector{display:none!important}main,.atlas main{display:block}.state{display:none!important}body[data-print=all] .state,.state.selected{display:block!important}body[data-print=all] .diagram{display:block!important}.diagram{margin:0;padding:0;border:0;border-radius:0}.diagram h2{font-size:19px!important}.diagram .legend{display:block!important}.full-labels{columns:2}.svg-wrap svg{max-height:235mm}.diagram:last-child{break-after:page}body[data-print=details] main{display:none!important}body[data-print=details] #printdetails{display:block}#printdetails .diagram{display:block!important}#printdetails svg{max-height:220mm}}
        </style></head><body class='\(peek ? "peek" : "") \(atlas ? "atlas" : "")' data-gesture=taps data-print=current>
        <header class=toolbar><strong>PanaLux · Panel Reference</strong><label>Map <select id=map onchange='selectMap(this.value)'>\(options)</select></label><div class=tools><button id=taps class=active onclick="gesture('taps')">Turn / Tap</button><button id=holds onclick="gesture('holds')">Press / Hold</button><button id=both onclick="gesture('both')">Both views</button><button id=atlas onclick='allPanels()'>All modes</button></div><label>Zoom <select id=zoom onchange='zoomPanel(this.value)'><option value=full>Whole panel</option><option value=knobs>Knobs</option><option value=left>Left keys</option><option value=center>Centre keys</option><option value=right>Right keys</option><option value=wheels>Wheels</option></select></label><div class='tools print-tools'><button onclick='printGuide(false)'>Print this view / PDF…</button><button onclick='printGuide(true)'>Print complete guide / PDF…</button><button onclick='printDetails()'>Print enlarged sections…</button><button id=savepng onclick='savePNG()'>Save selected Turn / Tap PNG</button></div></header>
        <p class=hint>\(peek ? "Hold Previous Still + Next Still · release either to dismiss. You can click the view, mode and zoom controls while held." : "Choose a mode and gesture, or show all diagrams. Click any labeled physical control for its full assignments. Print uses the diagrams below; choose Save as PDF in the print dialog.")</p>
        <main>\(pages)</main><aside class=inspector id=details><strong>Click a control on the drawing</strong><span>Its full turn, press and hold assignments appear here.</span></aside>
        <script>
        const boxes={full:'0 0 1080 552',knobs:'25 20 1025 150',left:'35 170 135 335',center:'195 167 690 97',right:'912 170 134 335',wheels:'177 268 730 270'};
        function selectMap(i){document.querySelectorAll('.state').forEach(s=>s.classList.toggle('selected',s.dataset.index===String(i)));document.body.classList.remove('atlas');document.getElementById('atlas').classList.remove('active');document.getElementById('map').value=i;zoomPanel('full');}
        function gesture(g){document.body.dataset.gesture=g;['taps','holds','both'].forEach(id=>document.getElementById(id).classList.toggle('active',id===g));document.getElementById('savepng').textContent='Save selected '+(g==='holds'?'Press / Hold':'Turn / Tap')+' PNG';}
        function allPanels(){document.body.classList.toggle('atlas');document.getElementById('atlas').classList.toggle('active');zoomPanel('full');}
        function zoomPanel(z){document.getElementById('zoom').value=z;document.querySelectorAll('svg').forEach(s=>{s.setAttribute('viewBox',boxes[z]);const v=boxes[z].split(' ').map(Number);s.style.aspectRatio=v[2]+'/'+v[3];s.style.maxHeight=z==='full'?'':'72vh';s.style.width=z==='full'?'100%':'min(100%, '+(72*v[2]/v[3])+'vh)';});}
        function printGuide(all){document.body.dataset.print=all?'all':'current';if(all)zoomPanel('full');window.print();}
        function printDetails(){document.getElementById('printdetails')?.remove();const holder=document.createElement('div');holder.id='printdetails';const active=document.querySelector('.state.selected');const articles=document.body.dataset.gesture==='both'?[...active.querySelectorAll('.diagram')]:[active.querySelector(document.body.dataset.gesture==='holds'?'.holds':'.taps')];for(const original of articles){for(const z of ['knobs','center','left','right','wheels']){const a=original.cloneNode(true);a.querySelector('h2').append(document.createTextNode(' · '+({knobs:'Knobs',center:'Centre keys',left:'Left keys',right:'Right keys',wheels:'Wheels'}[z])));const svg=a.querySelector('svg');svg.setAttribute('viewBox',boxes[z]);svg.removeAttribute('style');const v=boxes[z].split(' ').map(Number);svg.style.aspectRatio=v[2]+'/'+v[3];svg.style.width='min(100%, '+(220*v[2]/v[3])+'mm)';holder.append(a);}}document.body.append(holder);document.body.dataset.print='details';window.print();}
        document.addEventListener('click',e=>{const c=e.target.closest('[data-ref]');if(!c)return;const d=document.getElementById('details');d.replaceChildren();for(const [heading,value] of [[c.dataset.name,''],['Turn / Tap',c.dataset.turn],['Press',c.dataset.press],['Hold',c.dataset.hold]]){if(!heading||(!value&&heading!==c.dataset.name))continue;const p=document.createElement('span');const b=document.createElement('strong');b.textContent=heading+(value?': ':'');p.append(b,document.createTextNode(value||''));d.append(p);}});
        document.addEventListener('keydown',e=>{if(e.target.closest('[data-ref]')&&(e.key==='Enter'||e.key===' ')){e.preventDefault();e.target.closest('[data-ref]').dispatchEvent(new MouseEvent('click',{bubbles:true}));}});
        async function savePNG(){
          const article=document.querySelector('.state.selected').querySelector(document.body.dataset.gesture==='holds'?'.holds':'.taps');
          const svg=article.querySelector('svg').cloneNode(true);svg.setAttribute('xmlns','http://www.w3.org/2000/svg');svg.setAttribute('viewBox','0 0 1080 552');svg.setAttribute('width','3240');svg.setAttribute('height','1656');svg.removeAttribute('style');
          const url=URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(svg)],{type:'image/svg+xml'}));
          try{const img=new Image();img.src=url;await img.decode();const canvas=document.createElement('canvas');canvas.width=3240;const ctx=canvas.getContext('2d');ctx.font='28px Arial';
            const lines=[];for(const p of article.querySelectorAll('.full-labels p')){let line='';for(const word of p.textContent.split(' ')){if(ctx.measureText(line+' '+word).width>3150){lines.push(line);line='';}line+=(line?' ':'')+word;}if(line)lines.push(line);}
            canvas.height=1840+lines.length*38;ctx.fillStyle='white';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.fillStyle='#18333e';ctx.font='bold 38px Arial';ctx.fillText('PanaLux · '+article.querySelector('h2').textContent,36,48);ctx.font='23px Arial';ctx.fillText(article.querySelector('.context').textContent,36,90);ctx.drawImage(img,0,124);ctx.font='28px Arial';lines.forEach((line,i)=>ctx.fillText(line,36,1820+i*38));
            const a=document.createElement('a');a.download='PanaLux '+article.querySelector('h2').textContent.replace(/[^a-zA-Z0-9 -]/g,'-')+'.png';a.href=canvas.toDataURL('image/png');a.click();
          }catch(e){alert('Could not save the image. Use Print / Save as PDF instead.');}finally{URL.revokeObjectURL(url);}
        }
        function fitReference(){} // The SVG scales with the viewport; zoom remains user-controlled.
        </script></body></html>
        """
    }
}
