// recolor.js - recolor Claude's icon with Core Image (JavaScript for Automation, built into macOS).
//   osascript -l JavaScript recolor.js <src.png> <dst.png> <RRGGBB>
// Hue -> target hue, saturation scaled, then a gamma curve that darkens the colored background
// toward the target brightness while pure white (the glyph) stays white.
ObjC.import('AppKit');
try { ObjC.import('CoreImage'); } catch (e) { ObjC.import('QuartzCore'); } // CIFilter lives in Core Image

const BRAND = { h: 15, s: 0.60, v: 0.85 }; // Claude's orange

function toHsv(hex) {
  const n = parseInt(hex, 16);
  const r = (n >> 16 & 255) / 255, g = (n >> 8 & 255) / 255, b = (n & 255) / 255;
  const max = Math.max(r, g, b), d = max - Math.min(r, g, b);
  let h = 0;
  if (d) h = max === r ? ((g - b) / d) % 6 : max === g ? (b - r) / d + 2 : (r - g) / d + 4;
  return { h: (h * 60 + 360) % 360, s: max ? d / max : 0, v: max };
}

function apply(name, image, params) {
  const f = $.CIFilter.filterWithName(name);
  f.setValueForKey(image, 'inputImage');
  for (const key in params) f.setValueForKey($.NSNumber.numberWithDouble(params[key]), key);
  return f.valueForKey('outputImage');
}

function run(argv) {
  const [src, dst, hex] = argv;
  const t = toHsv(hex);
  let img = $.CIImage.imageWithContentsOfURL($.NSURL.fileURLWithPath(src));
  img = apply('CIHueAdjust', img, { inputAngle: (t.h - BRAND.h) * Math.PI / 180 });
  img = apply('CIColorControls', img, { inputSaturation: t.s / BRAND.s });
  img = apply('CIGammaAdjust', img, { inputPower: Math.log(Math.max(t.v, 0.05)) / Math.log(BRAND.v) });
  const rep = $.NSBitmapImageRep.alloc.initWithCIImage(img);
  const png = 4; // NSBitmapImageFileTypePNG
  rep.representationUsingTypeProperties(png, $({})).writeToFileAtomically(dst, true);
}
