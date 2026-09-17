import SwiftUI
import WebKit
import Combine

public struct InteractiveSVGView: NSViewRepresentable {
    @Binding var selectedControl: String?
    var activeControl: String?
    var isShiftHeld: Bool
    var baseBindings: [String: String]
    var shiftedBindings: [String: String]
    var heldSvgIds: [String]
    var overlayLabel: String
    var connectionsBySvg: [String: [[String: String]]]
    var foundSvgIds: [String]
    /// The hold key being edited. Selecting one knob then shows only that key's arrow to it.
    var focusOwnerSvg: String? = nil
    
    public init(
        selectedControl: Binding<String?>,
        activeControl: String? = nil,
        isShiftHeld: Bool = false,
        baseBindings: [String: String] = [:],
        shiftedBindings: [String: String] = [:],
        heldSvgIds: [String] = [],
        overlayLabel: String = "SHIFT",
        connectionsBySvg: [String: [[String: String]]] = [:],
        foundSvgIds: [String] = [],
        focusOwnerSvg: String? = nil
    ) {
        self.focusOwnerSvg = focusOwnerSvg
        self._selectedControl = selectedControl
        self.activeControl = activeControl
        self.isShiftHeld = isShiftHeld
        self.baseBindings = baseBindings
        self.shiftedBindings = shiftedBindings
        self.heldSvgIds = heldSvgIds
        self.overlayLabel = overlayLabel
        self.connectionsBySvg = connectionsBySvg
        self.foundSvgIds = foundSvgIds
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "controlSelected")
        contentController.add(context.coordinator, name: "commandDropped")
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        
        let webView = DropAwareWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.registerForDraggedTypes([.string])
        webView.onNativeDrop = { [weak webView] point, cmd in
            let js = "document.elementFromPoint(\(Double(point.x)), \(Double(point.y)))?.closest('[data-control-id]')?.dataset.controlId || ''"
            webView?.evaluateJavaScript(js) { result, _ in
                guard let svgId = result as? String, !svgId.isEmpty else { return }
                DispatchQueue.main.async {
                    StudioEngine.shared.applyDroppedCommand(commandId: cmd, ontoSvg: svgId)
                    context.coordinator.parent.selectedControl = PanelControlMapping.toProfileId(svgId)
                }
            }
        }
        context.coordinator.webView = webView
        context.coordinator.startPulses(on: webView)
        
        loadPanelSVG(into: webView)
        return webView
    }
    
    public func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        apply(to: webView, coordinator: context.coordinator)
    }
    
    fileprivate func apply(to webView: WKWebView, coordinator: Coordinator) {
        
        if let sel = selectedControl {
            coordinator.run("select", "if (window.selectControl) { window.selectControl('\(PanelControlMapping.toSvgId(sel))'); }", on: webView)
        }
        
        let found = foundSvgIds.sorted().map { "'\($0)'" }.joined(separator: ",")
        coordinator.run("found", "if (window.setFoundControls) { window.setFoundControls([\(found)]); }", on: webView)
        
        let held = heldSvgIds.sorted().map { "'\($0)'" }.joined(separator: ",")
        coordinator.run("held", "if (window.setHeldControls) { window.setHeldControls([\(held)]); }", on: webView)
        
        let label = overlayLabel.replacingOccurrences(of: "'", with: "")
        coordinator.run("overlay", "if (window.setShiftState) { window.setShiftState(\(isShiftHeld ? "true" : "false"), '\(label)'); }", on: webView)
        
        if let data = try? JSONSerialization.data(withJSONObject: connectionsBySvg, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            let escaped = json.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            coordinator.run("connections", "if (window.setConnections) { window.setConnections('\(escaped)'); }", on: webView)
        }
        
        coordinator.run("focusOwner", "if (window.setFocusOwner) { window.setFocusOwner('\(focusOwnerSvg ?? "")'); }", on: webView)
        pushBindings(to: webView)
    }
    
    fileprivate func pushBindings(to webView: WKWebView) {
        let payload: [String: Any] = [
            "base": baseBindings,
            "shifted": shiftedBindings
        ]
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let jsonStr = String(data: jsonData, encoding: .utf8) {
            let escaped = jsonStr.replacingOccurrences(of: "\\", with: "\\\\")
                                 .replacingOccurrences(of: "'", with: "\\'")
            let js = "if (window.updateBindingsPayload) { window.updateBindingsPayload('\(escaped)'); }"
            if let coordinator = webView.navigationDelegate as? Coordinator {
                coordinator.run("bindings", js, on: webView)
            } else {
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }
    }
    
    public static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "controlSelected")
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: "commandDropped")
    }
    
    private func loadPanelSVG(into webView: WKWebView) {
        guard let svgContent = loadSVGString() else {
            let errorHtml = "<html><body style='color:white;background:#101317;display:flex;align-items:center;justify-content:center;height:100vh;font-family:sans-serif;'><p>Could not load micro-color-panel.svg</p></body></html>"
            webView.loadHTMLString(errorHtml, baseURL: nil)
            return
        }
        
        webView.loadHTMLString(Self.pageHTML(svgContent: svgContent), baseURL: nil)
    }
    
    static func pageHTML(svgContent: String) -> String {
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          html, body {
            width: 100%;
            height: 100%;
            overflow: hidden;
            background: transparent;
            color: #ebf0f6;
            display: flex;
            align-items: center;
            justify-content: center;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            user-select: none;
            -webkit-user-select: none;
          }
          .canvas-wrapper {
            position: relative;
            width: 100%;
            height: 100%;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 14px;
          }
          svg {
            display: block;
            width: 100%;
            height: 100%;
            max-width: 100%;
            max-height: 100%;
            object-fit: contain;
          }
          text {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", Arial, sans-serif;
          }
          .control {
            cursor: pointer;
            outline: none;
            transition: stroke 0.15s ease, fill 0.15s ease, filter 0.15s ease;
          }
          .control text, .control .icon, .control .detail {
            pointer-events: none;
          }
          
          /* Rings & Trackballs Idle Depth */
          .control-ring .interactive-face {
            transition: stroke 0.2s ease, filter 0.2s ease;
          }
          .control-trackball .interactive-face {
            transition: stroke 0.2s ease, filter 0.2s ease;
          }
          
          /* Hover State */
          .control:hover .interactive-face {
            stroke: #38bdf8 !important;
            stroke-width: 2.0 !important;
            filter: drop-shadow(0 0 8px rgba(56, 189, 248, 0.65)) !important;
          }
          
          /* Selected State */
          .control[data-selected="true"] .interactive-face,
          .control.is-selected .interactive-face {
            fill: #1e3a5f !important;
            stroke: #0ea5e9 !important;
            stroke-width: 2.5 !important;
            filter: drop-shadow(0 0 12px rgba(14, 165, 233, 0.9)) !important;
          }
          .control[data-selected="true"] .control-label,
          .control.is-selected .control-label {
            fill: #ffffff !important;
            font-weight: 700 !important;
          }
          
          /* Live Hardware Active Glow (Neon Green) */
          .control[data-active="true"] .interactive-face {
            fill: #14532d !important;
            stroke: #22c55e !important;
            stroke-width: 3.0 !important;
            filter: drop-shadow(0 0 18px rgba(34, 197, 94, 0.95)) drop-shadow(0 0 30px rgba(34, 197, 94, 0.4)) !important;
          }
          .control[data-active="true"] .control-label {
            fill: #86efac !important;
            font-weight: 700 !important;
          }
          
          .hidden { display: none !important; }
          
          /* Find on Panel / tour highlight */
          @keyframes found-pulse {
            0%, 100% { filter: drop-shadow(0 0 6px rgba(250, 204, 21, 0.55)); }
            50% { filter: drop-shadow(0 0 22px rgba(250, 204, 21, 1.0)); }
          }
          .control[data-found="true"] .interactive-face {
            stroke: #facc15 !important;
            stroke-width: 3.0 !important;
            animation: found-pulse 1.1s ease-in-out infinite;
          }
          
          /* Drag and Drop Target Glow */
          .control.drag-hover .interactive-face {
            stroke: #f59e0b !important;
            fill: #451a03 !important;
            stroke-width: 3.0 !important;
            filter: drop-shadow(0 0 18px rgba(245, 158, 11, 0.9)) !important;
          }
          
          /* Floating Glass HUD Readout Pill */
          #hud-pill {
            position: absolute;
            bottom: 18px;
            left: 50%;
            transform: translateX(-50%);
            background: rgba(18, 24, 33, 0.92);
            backdrop-filter: blur(24px);
            -webkit-backdrop-filter: blur(24px);
            border: 1px solid rgba(255, 255, 255, 0.16);
            border-radius: 9999px;
            padding: 8px 20px;
            display: flex;
            align-items: center;
            gap: 10px;
            box-shadow: 0 14px 35px rgba(0, 0, 0, 0.65);
            pointer-events: none;
            opacity: 1;
            transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
            z-index: 50;
          }
          .control[data-held="true"] .interactive-face {
            fill: #14532d !important;
            stroke: #22c55e !important;
            stroke-width: 3.0 !important;
            filter: drop-shadow(0 0 18px rgba(34, 197, 94, 0.95)) drop-shadow(0 0 30px rgba(34, 197, 94, 0.4)) !important;
          }
          .control[data-held="true"] .control-label {
            fill: #86efac !important;
          }
          #arrow-overlay {
            position: absolute;
            inset: 0;
            width: 100%;
            height: 100%;
            pointer-events: none;
            overflow: visible;
            z-index: 40;
          }
          #link-layer {
            position: absolute;
            inset: 0;
            pointer-events: none;
            z-index: 45;
            transition: opacity 0.18s ease;
          }
          #link-layer.fading { opacity: 0; }
          .conn-line {
            fill: none;
            stroke: rgba(251, 146, 60, 0.85);
            stroke-width: 1.8;
            stroke-linecap: round;
            filter: drop-shadow(0 0 3px rgba(251, 146, 60, 0.45));
            animation: conn-draw 0.42s cubic-bezier(0.2, 0.9, 0.3, 1) both;
          }
          .conn-line.faint { stroke: rgba(251, 146, 60, 0.45); stroke-width: 1.3; }
          .conn-flow {
            fill: none;
            stroke: rgba(255, 237, 213, 0.9);
            stroke-width: 1.8;
            stroke-linecap: round;
            stroke-dasharray: 2 26;
            animation: conn-flow 1.4s linear infinite, conn-fade 0.3s ease both;
          }
          .conn-dot {
            fill: #fb923c;
            animation: conn-pop 0.35s cubic-bezier(0.2, 1.4, 0.4, 1) both;
            transform-box: fill-box;
            transform-origin: center;
          }
          @keyframes conn-draw {
            from { stroke-dashoffset: var(--len); stroke-dasharray: var(--len); opacity: 0; }
            20% { opacity: 1; }
            to { stroke-dashoffset: 0; stroke-dasharray: var(--len); opacity: 1; }
          }
          @keyframes conn-flow { to { stroke-dashoffset: -28; } }
          @keyframes conn-fade { from { opacity: 0; } to { opacity: 1; } }
          @keyframes conn-pop { from { transform: scale(0); } to { transform: scale(1); } }
          .control[data-linked="true"] .interactive-face {
            stroke: #fb923c !important;
            stroke-width: 2.4 !important;
            filter: drop-shadow(0 0 7px rgba(251, 146, 60, 0.55)) !important;
            transition: stroke 0.2s ease, filter 0.2s ease;
          }
          .link-tag {
            position: absolute;
            transform: translate(-50%, -100%);
            white-space: nowrap;
            padding: 3px 9px;
            border-radius: 999px;
            background: rgba(24, 24, 27, 0.88);
            -webkit-backdrop-filter: blur(12px);
            border: 1px solid rgba(251, 146, 60, 0.45);
            color: #fed7aa;
            font: 600 11px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
            box-shadow: 0 4px 14px rgba(0, 0, 0, 0.45);
            animation: tag-in 0.3s cubic-bezier(0.2, 0.9, 0.3, 1) both;
          }
          .link-tag.summary {
            font-size: 12px;
            padding: 5px 12px;
            border-color: rgba(251, 146, 60, 0.7);
          }
          .link-tag b { color: #fb923c; font-weight: 700; }
          @keyframes tag-in {
            from { opacity: 0; transform: translate(-50%, -80%) scale(0.92); }
            to { opacity: 1; transform: translate(-50%, -100%) scale(1); }
          }
          .badge-type {
            background: rgba(56, 189, 248, 0.22);
            color: #38bdf8;
            border-radius: 6px;
            padding: 2px 8px;
            font-size: 10px;
            font-weight: 700;
            text-transform: uppercase;
            letter-spacing: 0.05em;
          }
          .badge-shift {
            background: rgba(245, 158, 11, 0.25);
            color: #fbbf24;
            border-radius: 6px;
            padding: 2px 7px;
            font-size: 10px;
            font-weight: 700;
            text-transform: uppercase;
          }
          .pill-label {
            font-size: 13px;
            font-weight: 600;
            color: #f8fafc;
          }
          .pill-arrow {
            color: #64748b;
            font-size: 12px;
          }
          .pill-cmd {
            font-size: 13px;
            font-weight: 700;
            color: #fb923c;
          }
        </style>
        </head>
        <body>
          <div class="canvas-wrapper">
            \(svgContent)
            <svg id="arrow-overlay" xmlns="http://www.w3.org/2000/svg"></svg>
            <div id="link-layer"></div>
            <div id="hud-pill" class="hidden">
              <span class="badge-type" id="pill-type">ENCODER</span>
              <span class="badge-shift hidden" id="pill-shift">SHIFT</span>
              <span class="pill-label" id="pill-name">Y GAMMA</span>
              <span class="pill-arrow">→</span>
              <span class="pill-cmd" id="pill-cmd">Exposure</span>
            </div>
          </div>
          
          <script>
            const svg = document.getElementById('micro-color-panel');
            const hudPill = document.getElementById('hud-pill');
            const pillType = document.getElementById('pill-type');
            const pillShift = document.getElementById('pill-shift');
            const pillName = document.getElementById('pill-name');
            const pillCmd = document.getElementById('pill-cmd');
            
            let currentSelectedId = null;
            let hoveredControlId = null;
            let isShiftActive = false;
            let overlayLabel = 'SHIFT';
            let baseMap = {};
            let shiftedMap = {};
            let heldSet = new Set();
            let connectionMap = {};
            let focusOwner = '';
            const arrowOverlay = document.getElementById('arrow-overlay');
            
            window.updateBindingsPayload = function(jsonStr) {
              try {
                const data = JSON.parse(jsonStr);
                baseMap = data.base || {};
                shiftedMap = data.shifted || {};
                if (hoveredControlId) {
                  showPill(hoveredControlId);
                } else if (currentSelectedId) {
                  showPill(currentSelectedId);
                }
              } catch(e) {}
            };
            
            window.setHeldControls = function(ids) {
              heldSet = new Set(ids || []);
              for (const node of svg.querySelectorAll('[data-control-id]')) {
                const id = node.dataset.controlId;
                node.dataset.held = heldSet.has(id) ? 'true' : 'false';
                if (heldSet.has(id)) node.dataset.active = 'true';
              }
            };
            
            window.setFoundControls = function(ids) {
              const found = new Set(ids || []);
              for (const node of svg.querySelectorAll('[data-control-id]')) {
                node.dataset.found = found.has(node.dataset.controlId) ? 'true' : 'false';
              }
            };
            
            window.setConnections = function(jsonStr) {
              try { connectionMap = JSON.parse(jsonStr) || {}; } catch(e) { connectionMap = {}; }
              drawArrows(hoveredControlId || currentSelectedId);
            };
            
            window.setFocusOwner = function(id) {
              if (focusOwner === id) return;
              focusOwner = id || '';
              drawnFor = null;
              drawArrows(hoveredControlId || currentSelectedId);
            };
            
            window.setShiftState = function(isShifted, label) {
              isShiftActive = isShifted;
              if (label) overlayLabel = label;
              pillShift.textContent = overlayLabel || 'LAYER';
              if (hoveredControlId) {
                showPill(hoveredControlId);
              } else if (currentSelectedId) {
                showPill(currentSelectedId);
              }
            };
            
            const linkLayer = document.getElementById('link-layer');
            let drawnFor = null;
            
            function rectOf(id) {
              const el = svg.querySelector(`[data-control-id="${id}"]`);
              if (!el || !arrowOverlay) return null;
              const face = el.querySelector('.interactive-face') || el;
              const r = face.getBoundingClientRect();
              const root = arrowOverlay.getBoundingClientRect();
              if (!r.width || !r.height) return null;
              return { x: r.left - root.left, y: r.top - root.top, w: r.width, h: r.height,
                       cx: r.left + r.width / 2 - root.left, cy: r.top + r.height / 2 - root.top };
            }
            
            function clearLinks() {
              while (arrowOverlay.lastChild) arrowOverlay.removeChild(arrowOverlay.lastChild);
              linkLayer.replaceChildren();
              for (const node of svg.querySelectorAll('[data-linked="true"]')) node.dataset.linked = 'false';
            }
            
            function tag(html, x, y, extra) {
              const el = document.createElement('div');
              el.className = 'link-tag' + (extra ? ' ' + extra : '');
              el.innerHTML = html;
              el.style.left = x + 'px';
              el.style.top = y + 'px';
              linkLayer.appendChild(el);
              return el;
            }
            
            function esc(t) {
              return String(t).replace(/[&<>]/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;'}[c]));
            }
            
            // Hovering a key: soft curves to what it drives, one label per idea, never on the lines.
            function drawArrows(id) {
              if (!arrowOverlay) return;
              // A knob picked while editing a hold: one arrow from that key, labeled.
              let source = id;
              let links = id ? (connectionMap[id] || []).filter(l => l.to !== id) : [];
              let single = false;
              if (id && focusOwner && id !== focusOwner && !links.length) {
                const hit = (connectionMap[focusOwner] || []).find(l => l.to === id);
                source = focusOwner;
                links = [{ to: id, label: hit && hit.label !== 'Drop' ? hit.label : 'Pick a command' }];
                single = true;
              }
              const key = id ? source + '>' + id + '|' + JSON.stringify(links) : null;
              if (key === drawnFor) return;
              drawnFor = key;
              clearLinks();
              if (!id) return;
              const from = rectOf(source);
              if (!from || !links.length) return;
              const ns = 'http://www.w3.org/2000/svg';
              const faint = links.length > 8;
              
              links.forEach((link, i) => {
                const to = rectOf(link.to);
                if (!to) return;
                const target = svg.querySelector(`[data-control-id="${link.to}"]`);
                if (target) target.dataset.linked = 'true';
                
                // Leave the source from its edge, arrive at the target's edge, bow gently upward.
                const dx = to.cx - from.cx, dy = to.cy - from.cy;
                const dist = Math.max(1, Math.hypot(dx, dy));
                const ux = dx / dist, uy = dy / dist;
                const x1 = from.cx + ux * Math.min(from.w, from.h) * 0.5;
                const y1 = from.cy + uy * Math.min(from.w, from.h) * 0.5;
                const x2 = to.cx - ux * (Math.min(to.w, to.h) * 0.5 + 4);
                const y2 = to.cy - uy * (Math.min(to.w, to.h) * 0.5 + 4);
                const bow = Math.min(60, dist * 0.18);
                const mx = (x1 + x2) / 2 - uy * bow * Math.sign(ux || 1);
                const my = (y1 + y2) / 2 - Math.abs(ux) * bow;
                const d = `M ${x1} ${y1} Q ${mx} ${my} ${x2} ${y2}`;
                const delay = Math.min(i * 22, 300);
                
                const line = document.createElementNS(ns, 'path');
                line.setAttribute('d', d);
                line.setAttribute('class', 'conn-line' + (faint ? ' faint' : ''));
                arrowOverlay.appendChild(line);
                const len = line.getTotalLength();
                line.style.setProperty('--len', len);
                line.style.animationDelay = delay + 'ms';
                
                if (!faint) {
                  const flow = document.createElementNS(ns, 'path');
                  flow.setAttribute('d', d);
                  flow.setAttribute('class', 'conn-flow');
                  flow.style.animationDelay = `0ms, ${delay + 300}ms`;
                  arrowOverlay.appendChild(flow);
                }
                
                const dot = document.createElementNS(ns, 'circle');
                dot.setAttribute('cx', x2);
                dot.setAttribute('cy', y2);
                dot.setAttribute('r', faint ? 2.2 : 3.2);
                dot.setAttribute('class', 'conn-dot');
                dot.style.animationDelay = (delay + 260) + 'ms';
                arrowOverlay.appendChild(dot);
              });
              
              // Labels: if every target does the same thing, say it once by the key.
              const named = links.filter(l => l.label && l.label !== 'Drop' && l.label !== 'Layer');
              const kinds = [...new Set(named.map(l => l.label))];
              if (single) {
                const to = rectOf(links[0].to);
                if (to) tag(`<b>${esc(links[0].label)}</b>`, to.cx, to.y - 6, 'summary');
              } else if (kinds.length === 1 && links.length > 1) {
                const count = links.length;
                tag(`<b>${esc(kinds[0])}</b> · ${count} control${count === 1 ? '' : 's'}`, from.cx, from.y - 8, 'summary');
              } else if (kinds.length > 1) {
                named.forEach((l, i) => {
                  const to = rectOf(l.to);
                  if (!to) return;
                  const t = tag(esc(l.label), to.cx, to.y - 6);
                  t.style.animationDelay = Math.min(i * 22, 300) + 180 + 'ms';
                });
              } else if (links.some(l => l.label === 'Drop')) {
                tag('Click or drop onto a <b>knob, ring, or ball</b>', from.cx, from.y - 8, 'summary');
              }
            }
            
            function showPill(id) {
              const el = document.querySelector(`[data-control-id="${id}"]`);
              if (!el) {
                hudPill.classList.add('hidden');
                drawArrows(null);
                return;
              }
              const label = el.dataset.label || id;
              const type = el.dataset.controlType || 'control';
              
              const map = isShiftActive ? shiftedMap : baseMap;
              const binding = map[id] || (isShiftActive ? (baseMap[id] || 'Unassigned') : 'Unassigned');
              
              pillType.textContent = type.toUpperCase();
              if (isShiftActive) {
                pillShift.classList.remove('hidden');
              } else {
                pillShift.classList.add('hidden');
              }
              pillName.textContent = label;
              pillCmd.textContent = binding;
              hudPill.classList.remove('hidden');
              drawArrows(id);
            }
            
            window.selectControl = function(id) {
              currentSelectedId = id;
              for (const node of svg.querySelectorAll('[data-control-id]')) {
                node.dataset.selected = (node.dataset.controlId === id) ? 'true' : 'false';
              }
              if (!hoveredControlId) {
                showPill(id);
              } else {
                drawArrows(hoveredControlId);
              }
            };
            
            window.flashActiveControl = function(id) {
              const el = document.querySelector(`[data-control-id="${id}"]`);
              if (el) {
                el.dataset.active = 'true';
                clearTimeout(el._activeTimer);
                el._activeTimer = setTimeout(() => {
                  if (heldSet.has(id) || isShiftActive) return;
                  el.dataset.active = 'false';
                }, 350);
              }
            };
            
            // Event delegation on SVG controls
            svg.addEventListener('click', (event) => {
              const control = event.target.closest('[data-control-id]');
              if (!control) return;
              const id = control.dataset.controlId;
              window.selectControl(id);
              if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.controlSelected) {
                window.webkit.messageHandlers.controlSelected.postMessage(id);
              }
            });
            
            // Hover feedback
            svg.addEventListener('mouseover', (event) => {
              const control = event.target.closest('[data-control-id]');
              if (control) {
                hoveredControlId = control.dataset.controlId;
                showPill(hoveredControlId);
              }
            });
            svg.addEventListener('mouseout', (event) => {
              const related = event.relatedTarget ? event.relatedTarget.closest('[data-control-id]') : null;
              if (!related) {
                hoveredControlId = null;
                linkLayer.classList.add('fading');
                setTimeout(() => linkLayer.classList.remove('fading'), 200);
                if (currentSelectedId) {
                  showPill(currentSelectedId);
                } else {
                  hudPill.classList.add('hidden');
                }
              }
            });
            
            // HTML5 Drag and Drop support
            document.addEventListener('dragover', (e) => {
              e.preventDefault();
              e.dataTransfer.dropEffect = 'copy';
              const control = e.target.closest('[data-control-id]');
              for (const node of svg.querySelectorAll('.drag-hover')) {
                if (node !== control) node.classList.remove('drag-hover');
              }
              if (control) {
                control.classList.add('drag-hover');
                showPill(control.dataset.controlId);
              }
            });
            
            document.addEventListener('dragleave', (e) => {
              const control = e.target.closest('[data-control-id]');
              if (control) control.classList.remove('drag-hover');
            });
            
            document.addEventListener('drop', (e) => {
              e.preventDefault();
              const control = e.target.closest('[data-control-id]');
              if (control) {
                control.classList.remove('drag-hover');
                const controlId = control.dataset.controlId;
                const commandId = e.dataTransfer.getData('text/plain');
                if (commandId && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.commandDropped) {
                  window.webkit.messageHandlers.commandDropped.postMessage({
                    controlId: controlId,
                    commandId: commandId
                  });
                }
              }
            });
          </script>
        </body>
        </html>
        """
    }
    
    private func loadSVGString() -> String? {
        AppResources.string("micro-color-panel", "svg")
    }
    
    public class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: InteractiveSVGView
        weak var webView: WKWebView?
        
        init(_ parent: InteractiveSVGView) {
            self.parent = parent
        }
        
        private var lastScripts: [String: String] = [:]
        private var pulseCancellable: AnyCancellable?
        
        /// Skip scripts identical to the last one sent for the same purpose.
        func run(_ key: String, _ js: String, on webView: WKWebView) {
            guard lastScripts[key] != js else { return }
            lastScripts[key] = js
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        /// Live pulses arrive at USB speed; ten updates a second is plenty for the drawing.
        func startPulses(on webView: WKWebView) {
            pulseCancellable = StudioEngine.shared.controlPulse
                .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
                .sink { [weak webView] control in
                    let svgId = PanelControlMapping.toSvgId(control)
                    webView?.evaluateJavaScript("if (window.flashActiveControl) { window.flashActiveControl('\(svgId)'); }", completionHandler: nil)
                }
        }
        
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastScripts.removeAll()
            parent.apply(to: webView, coordinator: self)
        }
        
        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "controlSelected", let svgId = message.body as? String {
                DispatchQueue.main.async {
                    let mappedId = PanelControlMapping.toProfileId(svgId)
                    self.parent.selectedControl = mappedId
                    StudioEngine.shared.highlightHardwareControl(mappedId)
                }
            } else if message.name == "commandDropped", let dict = message.body as? [String: Any],
                      let svgId = dict["controlId"] as? String,
                      let cmdId = dict["commandId"] as? String {
                DispatchQueue.main.async {
                    StudioEngine.shared.applyDroppedCommand(commandId: cmdId, ontoSvg: svgId)
                    self.parent.selectedControl = PanelControlMapping.toProfileId(svgId)
                    let js = "if (window.flashActiveControl) { window.flashActiveControl('\(svgId)'); }"
                    self.webView?.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }
    }
}

final class DropAwareWebView: WKWebView {
    var onNativeDrop: ((CGPoint, String) -> Void)?
    
    private func pagePoint(_ sender: NSDraggingInfo) -> CGPoint {
        let p = convert(sender.draggingLocation, from: nil)
        return isFlipped ? p : CGPoint(x: p.x, y: bounds.height - p.y)
    }

    private func highlightDrop(at p: CGPoint?) {
        let js = p.map { p in
            "(function(){const c=document.elementFromPoint(\(Double(p.x)),\(Double(p.y)))?.closest('[data-control-id]');for(const n of document.querySelectorAll('.drag-hover')){if(n!==c)n.classList.remove('drag-hover');}if(c)c.classList.add('drag-hover');})()"
        } ?? "for(const n of document.querySelectorAll('.drag-hover'))n.classList.remove('drag-hover')"
        evaluateJavaScript(js, completionHandler: nil)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlightDrop(at: pagePoint(sender)); return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        highlightDrop(at: pagePoint(sender)); return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { highlightDrop(at: nil) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlightDrop(at: nil)
        let pb = sender.draggingPasteboard
        let cmd = pb.string(forType: .string)
            ?? pb.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
        guard let cmd, !cmd.isEmpty else { return false }
        onNativeDrop?(pagePoint(sender), cmd)
        return true
    }
}
