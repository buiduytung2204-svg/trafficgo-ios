/* Development fixture importer only. Not included in Flutter production source. */
async function importAdminQA14(storage, fixture) {
  if (fixture.simulation_only !== true || fixture.username !== 'admin') throw Error('Invalid QA fixture');
  const active = JSON.parse(storage.getItem('flutter.active-account-id') || 'null');
  if (active !== fixture.user_id) return {status: 'different-account'};
  const prefix = 'flutter.account:' + active + ':';
  const marker = prefix + 'qa14-admin-imported-v1';
  if (storage.getItem(marker)) return {status: 'already-imported'};
  const parse = (raw, fallback) => {
    if (raw === null) return fallback;
    const value = JSON.parse(raw);
    return typeof value === 'string' ? JSON.parse(value) : value;
  };
  const union = (old, added, key) => {
    if (!Array.isArray(old) || !Array.isArray(added)) throw Error('Invalid existing list; preserving data');
    const ids = new Set(old.map(key));
    return old.concat(added.filter(row => {
      const id = key(row); if (ids.has(id)) return false; ids.add(id); return true;
    }));
  };
  const pending = [];
  for (const [name, value] of Object.entries(fixture.preferences)) {
    const key = prefix + name;
    let merged = value;
    if (name === 'journeys.v1' || name === 'garage.v1') {
      const added = JSON.parse(value), old = parse(storage.getItem(key), {});
      merged = {...added, ...old};
      const fields = name === 'journeys.v1' ? ['journeys', 'expenses', 'completed'] : ['vehicles', 'items', 'history'];
      for (const field of fields) merged[field] = union(old[field] || [], added[field] || [], row => row.id);
      merged = JSON.stringify(merged);
    } else if (name === 'saved' || name === 'trips') {
      const added = JSON.parse(value), old = parse(storage.getItem(key), []);
      const identity = name === 'saved'
        ? row => JSON.stringify([row.name, row.coordinate])
        : row => JSON.stringify([row.name, row.vehicle, row.route?.id]);
      merged = JSON.stringify(union(old, added, identity));
    } else if (name === 'history') {
      merged = union(parse(storage.getItem(key), []), value, row => row);
    } else if (storage.getItem(key) !== null) {
      continue; // Preserve the admin's existing preferences.
    }
    pending.push([key, JSON.stringify(merged)]);
  }
  const backup = pending.map(([key]) => [key, storage.getItem(key)]);
  const backupKey = prefix + 'qa14-admin-backup-v1';
  try {
    if (!storage.getItem(backupKey)) storage.setItem(backupKey, JSON.stringify(backup));
    for (const [key, value] of pending) storage.setItem(key, value);
    storage.setItem(marker, JSON.stringify(fixture.date_until));
  } catch (error) {
    for (const [key, value] of backup) {
      if (value === null) storage.removeItem(key); else storage.setItem(key, value);
    }
    storage.removeItem(marker);
    throw error;
  }
  return {status: 'imported', account: 'admin', simulation_only: true};
}
if (typeof module !== 'undefined') module.exports = {importAdminQA14};
