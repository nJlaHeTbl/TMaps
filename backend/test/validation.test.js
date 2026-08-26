import assert from 'node:assert/strict';
import test from 'node:test';

import { testing } from '../src/index.js';

const validSubmission = {
  lat: 45.0156,
  lng: 78.3739,
  username: 'Асылбек',
  placeKind: 'community_toilet',
  name: null,
  isFree: true,
  cleanliness: 4,
  condition: 'Хорошее',
  hasPaper: true,
  hasSoap: true,
  wheelchairAccessible: null,
  phoneCharging: null,
  accessType: 'public',
  comment: 'Есть бумага и мыло',
};

test('accepts a valid Kazakhstan place submission', () => {
  assert.deepEqual(testing.validateSubmission(validSubmission), validSubmission);
});

test('accepts a named cafe submission', () => {
  const cafe = {
    ...validSubmission,
    placeKind: 'cafe',
    name: 'Кофейня у парка',
    accessType: 'customers',
  };
  assert.deepEqual(testing.validateSubmission(cafe), cafe);
});

test('rejects a submission outside Kazakhstan', () => {
  assert.throws(
    () => testing.validateSubmission({ ...validSubmission, lat: 35 }),
    /Широта/,
  );
});

test('rejects links and blocked content', () => {
  assert.throws(
    () => testing.validateSubmission({ ...validSubmission, comment: 'https://spam.test' }),
    /Ссылки запрещены/,
  );
  assert.throws(
    () => testing.validateSubmission({ ...validSubmission, comment: 'закладки тут' }),
    /опасный текст/,
  );
});

test('converts D1 integer booleans to JSON booleans', () => {
  assert.deepEqual(
    testing.normalizeRow({ id: 1, is_free: 1, has_paper: 0, has_soap: null }),
    { id: 1, is_free: true, has_paper: false, has_soap: null },
  );
});

test('allows only configured browser origins to write', () => {
  const env = { ALLOWED_ORIGINS: 'https://njlahetbl.github.io' };
  const allowed = new Request('https://api.test/api/votes', {
    headers: { origin: 'https://njlahetbl.github.io' },
  });
  const rejected = new Request('https://api.test/api/votes', {
    headers: { origin: 'https://example.com' },
  });
  assert.equal(testing.isAllowedOrigin(allowed, env), true);
  assert.equal(testing.isAllowedOrigin(rejected, env), false);
});

test('accepts a moderated location correction inside Kazakhstan', () => {
  const correction = {
    placeKey: 'curated:beach-toilet',
    currentLat: 45.019598,
    currentLng: 78.399912,
    proposedLat: 45.0197,
    proposedLng: 78.4001,
    username: 'Мирас',
    comment: null,
  };

  assert.deepEqual(testing.validateLocationCorrection(correction), correction);
});

test('rejects a location correction that does not move the marker', () => {
  const correction = {
    placeKey: 'osm:123',
    currentLat: 45.0156,
    currentLng: 78.3739,
    proposedLat: 45.0156,
    proposedLng: 78.3739,
    username: 'Мирас',
  };

  assert.throws(
    () => testing.validateLocationCorrection(correction),
    /Передвинь метку/,
  );
});
