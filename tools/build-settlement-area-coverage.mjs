import fs from 'node:fs';
import path from 'node:path';

function parseArguments(argv) {
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const name = argv[index];
    const value = argv[index + 1];
    if (!name?.startsWith('--') || value === undefined) {
      throw new Error(`Invalid argument near ${name ?? '<end>'}.`);
    }
    values.set(name, value);
  }
  for (const name of ['--catalog', '--candidates', '--overrides', '--output']) {
    if (!values.has(name)) throw new Error(`Missing required argument ${name}.`);
  }
  return Object.fromEntries(values);
}

function readJson(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Required JSON file not found: ${filePath}`);
  }
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
}

const epsilon = 1e-7;

function cross(a, b, c) {
  return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
}

function pointOnSegment(point, start, end) {
  if (Math.abs(cross(start, end, point)) > epsilon) return false;
  return point.x >= Math.min(start.x, end.x) - epsilon
    && point.x <= Math.max(start.x, end.x) + epsilon
    && point.y >= Math.min(start.y, end.y) - epsilon
    && point.y <= Math.max(start.y, end.y) + epsilon;
}

function pointInPolygon(point, polygon) {
  if (polygon.length < 3) return false;
  let inside = false;
  for (let index = 0; index < polygon.length; index += 1) {
    const next = (index + 1) % polygon.length;
    const start = polygon[index];
    const end = polygon[next];
    if (pointOnSegment(point, start, end)) return true;
    if ((start.y > point.y) !== (end.y > point.y)) {
      const crossingX = ((end.x - start.x) * (point.y - start.y))
        / (end.y - start.y) + start.x;
      if (point.x < crossingX) inside = !inside;
    }
  }
  return inside;
}

function areaContainsPoint(area, point) {
  const bounds = area.bounds;
  if (bounds && (point.x < bounds.minX || point.x > bounds.maxX
      || point.y < bounds.minY || point.y > bounds.maxY)) {
    return false;
  }
  return pointInPolygon(point, area.polygon ?? []);
}

function anchorId(candidate) {
  return `${candidate.slot}:${candidate.entityName}`;
}

function compareText(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function main() {
  const args = parseArguments(process.argv.slice(2));
  const catalog = readJson(args['--catalog']);
  const candidatePolicy = readJson(args['--candidates']);
  const overridePolicy = readJson(args['--overrides']);
  const areasByRegion = Map.groupBy(catalog.areas, (area) => area.region);
  const candidateGroups = Map.groupBy(
    candidatePolicy.candidates.filter((candidate) => candidate.enabled),
    (candidate) => `${candidate.gameRegion}/${candidate.settlement}`,
  );
  const overrides = new Map(overridePolicy.settlements.map(
    (override) => [`${override.gameRegion}/${override.settlement}`, override],
  ));

  const settlements = [];
  for (const key of [...candidateGroups.keys()].sort(compareText)) {
    const [gameRegion, settlement] = key.split('/');
    const candidates = candidateGroups.get(key).toSorted((a, b) => a.slot - b.slot);
    const override = overrides.get(key);
    const forced = new Set([
      ...(override?.forceIncludeGuids ?? []),
      ...(override?.primaryGuid ? [override.primaryGuid] : []),
    ]);
    const relevantGuids = [];
    const coverageByGuid = {};
    for (const area of areasByRegion.get(gameRegion) ?? []) {
      const coverage = candidates
        .filter((candidate) => areaContainsPoint(area, candidate.position))
        .map(anchorId);
      const semanticText = `${area.name ?? ''} ${area.editorLayer ?? ''} ${area.label ?? ''}`
        .toLowerCase();
      if (coverage.length === 0
          && !semanticText.includes(settlement.toLowerCase())
          && !forced.has(area.guid)) {
        continue;
      }
      relevantGuids.push(area.guid);
      coverageByGuid[area.guid.toLowerCase()] = coverage;
    }
    settlements.push({
      gameRegion,
      settlement,
      areaGuids: relevantGuids.toSorted(compareText),
      coverageByGuid,
    });
  }
  writeJson(args['--output'], { schemaVersion: 1, settlements });
  console.log(`Built settlement area coverage: settlements=${settlements.length}`);
}

try {
  main();
} catch (error) {
  console.error(error.stack ?? error.message);
  process.exitCode = 1;
}
