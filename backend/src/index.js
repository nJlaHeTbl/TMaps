const DEFAULT_ORIGINS = [
  'https://njlahetbl.github.io',
  'http://localhost:3000',
  'http://localhost:4173',
];

const PLACE_KINDS = new Set([
  'community_toilet',
  'cafe',
  'fuel',
  'organization',
  'phone_charging',
  'ev_charging',
  'water',
]);
const CONDITIONS = new Set(['Хорошее', 'Среднее', 'Плохое']);
const ACCESS_TYPES = new Set([
  'public',
  'customers',
  'permissive',
  'destination',
  'unknown',
]);
const PEDESTRIAN_ALERT_TYPES = new Set([
  'open',
  'closed',
  'ice',
  'construction',
  'snow',
  'flooding',
  'obstacle',
]);
const BLOCKED_FRAGMENTS = [
  'nigger',
  'nigga',
  'пидор',
  'котак',
  'закладк',
  'наркотик',
  'сдох',
];
const URL_PATTERN = /(https?:\/\/|www\.|t\.me\/|wa\.me\/)/i;
const CONTROL_PATTERN = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/;

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (error) {
      if (error instanceof HttpError) {
        return json(request, env, { error: error.message }, error.status);
      }
      console.error(error);
      return json(
        request,
        env,
        { error: 'Сервис временно недоступен' },
        500,
      );
    }
  },
};

async function route(request, env) {
  const url = new URL(request.url);
  const method = request.method.toUpperCase();

  if (method === 'OPTIONS') {
    return new Response(null, {
      status: 204,
      headers: corsHeaders(request, env),
    });
  }

  if (!['GET', 'HEAD'].includes(method) && !isAllowedOrigin(request, env)) {
    throw new HttpError(403, 'Этот сайт не может изменять данные TMaps');
  }

  if (method === 'GET' && url.pathname === '/api/health') {
    return json(request, env, { ok: true, service: 'tmaps-community-api' });
  }
  if (method === 'GET' && url.pathname === '/api/places') {
    const result = await env.DB.prepare(
      'SELECT * FROM toilets ORDER BY created_at DESC LIMIT 5000',
    ).all();
    return json(request, env, { places: normalizeRows(result.results) });
  }
  if (method === 'GET' && url.pathname === '/api/reports') {
    const result = await env.DB.prepare(
      'SELECT * FROM toilet_reports ORDER BY created_at DESC LIMIT 5000',
    ).all();
    return json(request, env, { reports: normalizeRows(result.results) });
  }
  if (method === 'GET' && url.pathname === '/api/votes') {
    const result = await env.DB.prepare(
      `SELECT place_key,
        SUM(CASE WHEN is_current = 1 THEN 1 ELSE 0 END) AS likes,
        SUM(CASE WHEN is_current = 0 THEN 1 ELSE 0 END) AS dislikes
       FROM place_votes GROUP BY place_key`,
    ).all();
    return json(request, env, { votes: result.results });
  }
  if (method === 'GET' && url.pathname === '/api/location-overrides') {
    const result = await env.DB.prepare(
      'SELECT * FROM place_location_overrides ORDER BY updated_at DESC LIMIT 5000',
    ).all();
    return json(request, env, { overrides: normalizeRows(result.results) });
  }
  if (method === 'GET' && url.pathname === '/api/community-reviews') {
    const result = await env.DB.prepare(
      `SELECT
         submission.id AS submission_id,
         submission.lat,
         submission.lng,
         submission.place_kind,
         submission.name,
         submission.is_free,
         submission.cleanliness,
         submission.condition,
         submission.has_paper,
         submission.has_soap,
         submission.wheelchair_accessible,
         submission.phone_charging,
         submission.access_type,
         submission.created_at,
         datetime(submission.created_at, '+24 hours') AS review_available_at,
         SUM(CASE WHEN vote.is_valid = 1 THEN 1 ELSE 0 END) AS confirmation_count,
         SUM(CASE WHEN vote.is_valid = 0 THEN 1 ELSE 0 END) AS rejection_count
       FROM place_submissions AS submission
       LEFT JOIN place_submission_review_votes AS vote
         ON vote.submission_id = submission.id
       WHERE submission.status = 'pending'
         AND datetime(submission.created_at) <= datetime('now', '-24 hours')
       GROUP BY submission.id
       ORDER BY submission.created_at DESC
       LIMIT 500`,
    ).all();
    return json(request, env, {
      submissions: normalizeRows(result.results),
    });
  }
  if (method === 'GET' && url.pathname === '/api/help-requests') {
    const result = await env.DB.prepare(
      `SELECT place_key, request_type, created_at, expires_at
       FROM place_help_requests
       WHERE datetime(expires_at) > datetime('now')
       ORDER BY created_at DESC LIMIT 500`,
    ).all();
    return json(request, env, { requests: result.results });
  }
  if (method === 'GET' && url.pathname === '/api/pedestrian-alerts') {
    const result = await env.DB.prepare(
      `SELECT id, lat, lng, alert_type, username, description,
         created_at, expires_at
       FROM pedestrian_alerts
       WHERE datetime(expires_at) > datetime('now')
       ORDER BY created_at DESC LIMIT 500`,
    ).all();
    return json(request, env, { alerts: normalizeRows(result.results) });
  }
  if (method === 'POST' && url.pathname === '/api/submissions') {
    return submitPlace(request, env);
  }
  if (method === 'POST' && url.pathname === '/api/reports') {
    return submitReport(request, env);
  }
  if (method === 'POST' && url.pathname === '/api/votes') {
    return castVote(request, env);
  }
  if (method === 'POST' && url.pathname === '/api/location-corrections') {
    return submitLocationCorrection(request, env);
  }
  if (method === 'POST' && url.pathname === '/api/help-requests') {
    return requestPaperHelp(request, env);
  }
  if (method === 'POST' && url.pathname === '/api/pedestrian-alerts') {
    return reportPedestrianAlert(request, env);
  }

  const communityReviewMatch = url.pathname.match(
    /^\/api\/community-reviews\/(\d+)\/votes$/,
  );
  if (method === 'POST' && communityReviewMatch) {
    return reviewSubmission(
      request,
      env,
      Number(communityReviewMatch[1]),
    );
  }
  if (method === 'GET' && url.pathname === '/api/admin/submissions') {
    requireAdmin(request, env);
    const status = url.searchParams.get('status') || 'pending';
    if (!['pending', 'approved', 'rejected'].includes(status)) {
      throw new HttpError(400, 'Неизвестный статус');
    }
    const result = await env.DB.prepare(
      'SELECT * FROM place_submissions WHERE status = ? ORDER BY created_at DESC LIMIT 500',
    ).bind(status).all();
    return json(request, env, { submissions: normalizeRows(result.results) });
  }
  if (method === 'GET' && url.pathname === '/api/admin/location-corrections') {
    requireAdmin(request, env);
    const status = url.searchParams.get('status') || 'pending';
    if (!['pending', 'approved', 'rejected'].includes(status)) {
      throw new HttpError(400, 'Неизвестный статус');
    }
    const result = await env.DB.prepare(
      `SELECT * FROM place_location_corrections
       WHERE status = ? ORDER BY created_at DESC LIMIT 500`,
    ).bind(status).all();
    return json(request, env, { corrections: normalizeRows(result.results) });
  }

  const moderationMatch = url.pathname.match(
    /^\/api\/admin\/submissions\/(\d+)$/,
  );
  if (method === 'PATCH' && moderationMatch) {
    requireAdmin(request, env);
    return moderateSubmission(request, env, Number(moderationMatch[1]));
  }

  const locationModerationMatch = url.pathname.match(
    /^\/api\/admin\/location-corrections\/(\d+)$/,
  );
  if (method === 'PATCH' && locationModerationMatch) {
    requireAdmin(request, env);
    return moderateLocationCorrection(
      request,
      env,
      Number(locationModerationMatch[1]),
    );
  }

  if (method === 'GET' && !url.pathname.startsWith('/api/') && env.ASSETS) {
    return env.ASSETS.fetch(request);
  }

  throw new HttpError(404, 'Метод не найден');
}

async function submitPlace(request, env) {
  const body = await readJson(request);
  const input = validateSubmission(body);
  await verifyTurnstile(body.turnstileToken, request, env);
  await enforceRateLimit(request, env, 'submission', 5, 3600);

  const result = await env.DB.prepare(
    `INSERT INTO place_submissions
      (lat, lng, username, place_kind, name, is_free, cleanliness, condition,
       has_paper, has_soap, wheelchair_accessible, phone_charging,
       access_type, submitter_key, comment)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     RETURNING id`,
  ).bind(
    input.lat,
    input.lng,
    input.username,
    input.placeKind,
    input.name,
    boolInt(input.isFree),
    input.cleanliness,
    input.condition,
    nullableBoolInt(input.hasPaper),
    nullableBoolInt(input.hasSoap),
    nullableBoolInt(input.wheelchairAccessible),
    nullableBoolInt(input.phoneCharging),
    input.accessType,
    input.deviceKey,
    input.comment,
  ).first();

  return json(request, env, { id: result.id, status: 'pending' }, 201);
}

async function submitReport(request, env) {
  const body = await readJson(request);
  const input = validateReport(body);
  await verifyTurnstile(body.turnstileToken, request, env);
  await enforceRateLimit(request, env, 'report', 20, 3600);

  const report = await env.DB.prepare(
    `INSERT INTO toilet_reports
      (place_key, lat, lng, username, cleanliness, condition, is_free, has_toilet,
       has_paper, has_soap, wheelchair_accessible, phone_charging,
       access_type, comment)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     RETURNING *`,
  ).bind(
    input.placeKey,
    input.lat,
    input.lng,
    input.username,
    input.cleanliness,
    input.condition,
    nullableBoolInt(input.isFree),
    nullableBoolInt(input.hasToilet),
    nullableBoolInt(input.hasPaper),
    nullableBoolInt(input.hasSoap),
    nullableBoolInt(input.wheelchairAccessible),
    nullableBoolInt(input.phoneCharging),
    input.accessType,
    input.comment,
  ).first();

  return json(request, env, { report: normalizeRow(report) }, 201);
}

async function castVote(request, env) {
  const body = await readJson(request);
  const placeKey = requiredText(body.placeKey, 'Точка', 3, 120);
  const voterKey = requiredText(body.voterKey, 'Ключ устройства', 12, 80);
  if (typeof body.isCurrent !== 'boolean') {
    throw new HttpError(400, 'Некорректный голос');
  }
  await enforceRateLimit(request, env, 'vote', 120, 3600);

  await env.DB.prepare(
    `INSERT INTO place_votes (place_key, voter_key, is_current)
     VALUES (?, ?, ?)
     ON CONFLICT (place_key, voter_key) DO UPDATE SET
       is_current = excluded.is_current,
       created_at = CURRENT_TIMESTAMP`,
  ).bind(placeKey, voterKey, boolInt(body.isCurrent)).run();

  return json(request, env, { ok: true });
}

async function reviewSubmission(request, env, submissionId) {
  const body = await readJson(request);
  const voterKey = requiredText(body.voterKey, 'Ключ устройства', 12, 80);
  if (typeof body.isValid !== 'boolean') {
    throw new HttpError(400, 'Некорректное подтверждение');
  }
  await enforceRateLimit(request, env, 'submission-review', 60, 3600);

  const submission = await env.DB.prepare(
    `SELECT * FROM place_submissions
     WHERE id = ? AND status = 'pending'
       AND datetime(created_at) <= datetime('now', '-24 hours')`,
  ).bind(submissionId).first();
  if (!submission) {
    throw new HttpError(404, 'Заявка ещё закрыта или уже обработана');
  }
  if (submission.submitter_key && submission.submitter_key === voterKey) {
    throw new HttpError(400, 'Свою заявку должен подтвердить другой человек');
  }

  await env.DB.prepare(
    `INSERT INTO place_submission_review_votes
       (submission_id, voter_key, is_valid)
     VALUES (?, ?, ?)
     ON CONFLICT (submission_id, voter_key) DO UPDATE SET
       is_valid = excluded.is_valid,
       updated_at = CURRENT_TIMESTAMP`,
  ).bind(submissionId, voterKey, boolInt(body.isValid)).run();

  const totals = await env.DB.prepare(
    `SELECT
       SUM(CASE WHEN is_valid = 1 THEN 1 ELSE 0 END) AS confirmations,
       SUM(CASE WHEN is_valid = 0 THEN 1 ELSE 0 END) AS rejections
     FROM place_submission_review_votes WHERE submission_id = ?`,
  ).bind(submissionId).first();
  const confirmations = Number(totals.confirmations || 0);
  const rejections = Number(totals.rejections || 0);
  let status = 'pending';

  if (confirmations >= 2 && confirmations >= rejections + 2) {
    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO toilets
          (lat, lng, username, name, is_free, cleanliness, condition, comment,
           place_kind, has_toilet, has_paper, has_soap, wheelchair_accessible,
           phone_charging, access_type, submission_id)
         SELECT lat, lng, username, name, is_free, cleanliness, condition, comment,
           place_kind,
           CASE WHEN place_kind = 'community_toilet' THEN 1 ELSE 0 END,
           has_paper, has_soap, wheelchair_accessible, phone_charging,
           access_type, id
         FROM place_submissions WHERE id = ? AND status = 'pending'`,
      ).bind(submissionId),
      env.DB.prepare(
        `UPDATE place_submissions SET
           status = 'approved', reviewed_at = CURRENT_TIMESTAMP,
           published_toilet_id = (SELECT id FROM toilets WHERE submission_id = ?)
         WHERE id = ? AND status = 'pending'`,
      ).bind(submissionId, submissionId),
      duplicateSubmissionDismissal(env, submission),
    ]);
    status = 'approved';
  } else if (rejections >= 3 && rejections >= confirmations + 2) {
    await env.DB.prepare(
      `UPDATE place_submissions
       SET status = 'rejected', reviewed_at = CURRENT_TIMESTAMP
       WHERE id = ? AND status = 'pending'`,
    ).bind(submissionId).run();
    status = 'rejected';
  }

  return json(request, env, {
    review: {
      status,
      confirmation_count: confirmations,
      rejection_count: rejections,
    },
  });
}

async function requestPaperHelp(request, env) {
  const body = await readJson(request);
  const placeKey = requiredText(body.placeKey, 'Точка', 3, 120);
  const lat = boundedNumber(body.lat, 'Широта', -90, 90);
  const lng = boundedNumber(body.lng, 'Долгота', -180, 180);
  const requesterKey = requiredText(
    body.requesterKey,
    'Ключ устройства',
    12,
    80,
  );
  await enforceRateLimit(request, env, 'paper-help', 10, 3600);

  const expiresAt = new Date(Date.now() + 45 * 60 * 1000).toISOString();
  await env.DB.prepare(
    `INSERT INTO place_help_requests
       (place_key, lat, lng, requester_key, request_type, created_at, expires_at)
     VALUES (?, ?, ?, ?, 'paper', CURRENT_TIMESTAMP, ?)
     ON CONFLICT (place_key) DO UPDATE SET
       lat = excluded.lat,
       lng = excluded.lng,
       requester_key = excluded.requester_key,
       request_type = excluded.request_type,
       created_at = excluded.created_at,
       expires_at = excluded.expires_at`,
  ).bind(placeKey, lat, lng, requesterKey, expiresAt).run();
  return json(request, env, { expiresAt }, 201);
}

async function reportPedestrianAlert(request, env) {
  const body = await readJson(request);
  const lat = boundedNumber(body.lat, 'Широта', 40.45, 55.55);
  const lng = boundedNumber(body.lng, 'Долгота', 46.45, 87.4);
  const alertType = requiredText(body.alertType, 'Состояние дороги', 2, 20);
  if (!PEDESTRIAN_ALERT_TYPES.has(alertType)) {
    throw new HttpError(400, 'Неизвестное состояние дороги');
  }
  const username = safeUserText(body.username, 'Имя', 2, 30);
  const reporterKey = requiredText(
    body.reporterKey,
    'Ключ устройства',
    12,
    80,
  );
  const description = optionalSafeText(body.description, 'Комментарий', 240);
  await enforceRateLimit(request, env, 'pedestrian-alert', 6, 3600);

  const durations = {
    open: 6 * 60 * 60 * 1000,
    construction: 3 * 24 * 60 * 60 * 1000,
    closed: 24 * 60 * 60 * 1000,
  };
  const expiresAt = new Date(
    Date.now() + (durations[alertType] || 12 * 60 * 60 * 1000),
  ).toISOString();

  if (alertType === 'open') {
    await env.DB.prepare(
      `UPDATE pedestrian_alerts SET expires_at = CURRENT_TIMESTAMP
       WHERE alert_type <> 'open' AND datetime(expires_at) > datetime('now')
         AND abs(lat - ?) <= 0.00065 AND abs(lng - ?) <= 0.0009`,
    ).bind(lat, lng).run();
  }

  const existing = await env.DB.prepare(
    `SELECT id FROM pedestrian_alerts
     WHERE reporter_key = ? AND alert_type = ?
       AND datetime(expires_at) > datetime('now')
       AND abs(lat - ?) <= 0.00065 AND abs(lng - ?) <= 0.0009
     ORDER BY created_at DESC LIMIT 1`,
  ).bind(reporterKey, alertType, lat, lng).first();

  if (existing) {
    await env.DB.prepare(
      `UPDATE pedestrian_alerts SET lat = ?, lng = ?, username = ?,
         description = ?, created_at = CURRENT_TIMESTAMP, expires_at = ?
       WHERE id = ?`,
    ).bind(
      lat,
      lng,
      username,
      description,
      expiresAt,
      existing.id,
    ).run();
    return json(request, env, { id: existing.id }, 200);
  }

  const result = await env.DB.prepare(
    `INSERT INTO pedestrian_alerts
       (lat, lng, alert_type, username, description, reporter_key, expires_at)
     VALUES (?, ?, ?, ?, ?, ?, ?) RETURNING id`,
  ).bind(
    lat,
    lng,
    alertType,
    username,
    description,
    reporterKey,
    expiresAt,
  ).first();
  return json(request, env, { id: result.id }, 201);
}

function duplicateSubmissionDismissal(env, submission) {
  return env.DB.prepare(
    `UPDATE place_submissions SET status = 'rejected', reviewed_at = CURRENT_TIMESTAMP
     WHERE status = 'pending' AND id <> ? AND place_kind = ?
       AND abs(lat - ?) <= 0.00008 AND abs(lng - ?) <= 0.00008
       AND ((name IS NULL AND ? IS NULL) OR lower(trim(name)) = lower(trim(?)))`,
  ).bind(
    submission.id,
    submission.place_kind,
    submission.lat,
    submission.lng,
    submission.name,
    submission.name,
  );
}

async function submitLocationCorrection(request, env) {
  const body = await readJson(request);
  const input = validateLocationCorrection(body);
  await verifyTurnstile(body.turnstileToken, request, env);
  await enforceRateLimit(request, env, 'location-correction', 10, 3600);

  const result = await env.DB.prepare(
    `INSERT INTO place_location_corrections
      (place_key, current_lat, current_lng, proposed_lat, proposed_lng,
       username, comment)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     RETURNING id`,
  ).bind(
    input.placeKey,
    input.currentLat,
    input.currentLng,
    input.proposedLat,
    input.proposedLng,
    input.username,
    input.comment,
  ).first();

  return json(request, env, { id: result.id, status: 'pending' }, 201);
}

async function moderateSubmission(request, env, id) {
  const body = await readJson(request);
  const status = body.status;
  if (!['approved', 'rejected'].includes(status)) {
    throw new HttpError(400, 'Выбери approved или rejected');
  }

  const submission = await env.DB.prepare(
    'SELECT * FROM place_submissions WHERE id = ? AND status = \'pending\'',
  ).bind(id).first();
  if (!submission) throw new HttpError(404, 'Заявка уже обработана или не найдена');

  if (status === 'rejected') {
    await env.DB.prepare(
      `UPDATE place_submissions
       SET status = 'rejected', reviewed_at = CURRENT_TIMESTAMP
       WHERE id = ? AND status = 'pending'`,
    ).bind(id).run();
    return json(request, env, { ok: true, status });
  }

  const statements = [
    env.DB.prepare(
      `INSERT INTO toilets
        (lat, lng, username, name, is_free, cleanliness, condition, comment,
         place_kind, has_toilet, has_paper, has_soap, wheelchair_accessible,
         phone_charging, access_type, submission_id)
       SELECT lat, lng, username, name, is_free, cleanliness, condition, comment,
         place_kind,
         CASE WHEN place_kind = 'community_toilet' THEN 1 ELSE 0 END,
         has_paper, has_soap, wheelchair_accessible, phone_charging,
         access_type, id
       FROM place_submissions WHERE id = ? AND status = 'pending'`,
    ).bind(id),
    env.DB.prepare(
      `UPDATE place_submissions SET
         status = 'approved',
         reviewed_at = CURRENT_TIMESTAMP,
         published_toilet_id = (SELECT id FROM toilets WHERE submission_id = ?)
       WHERE id = ? AND status = 'pending'`,
    ).bind(id, id),
    duplicateSubmissionDismissal(env, submission),
  ];
  await env.DB.batch(statements);
  return json(request, env, { ok: true, status });
}

async function moderateLocationCorrection(request, env, id) {
  const body = await readJson(request);
  const status = body.status;
  if (!['approved', 'rejected'].includes(status)) {
    throw new HttpError(400, 'Выбери approved или rejected');
  }

  const correction = await env.DB.prepare(
    `SELECT * FROM place_location_corrections
     WHERE id = ? AND status = 'pending'`,
  ).bind(id).first();
  if (!correction) {
    throw new HttpError(404, 'Исправление уже обработано или не найдено');
  }

  if (status === 'rejected') {
    await env.DB.prepare(
      `UPDATE place_location_corrections
       SET status = 'rejected', reviewed_at = CURRENT_TIMESTAMP
       WHERE id = ? AND status = 'pending'`,
    ).bind(id).run();
    return json(request, env, { ok: true, status });
  }

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO place_location_overrides
        (place_key, lat, lng, location_correction_id, updated_at)
       VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
       ON CONFLICT (place_key) DO UPDATE SET
         lat = excluded.lat,
         lng = excluded.lng,
         location_correction_id = excluded.location_correction_id,
         updated_at = excluded.updated_at`,
    ).bind(
      correction.place_key,
      correction.proposed_lat,
      correction.proposed_lng,
      correction.id,
    ),
    env.DB.prepare(
      `UPDATE place_location_corrections
       SET status = 'approved', reviewed_at = CURRENT_TIMESTAMP
       WHERE id = ? AND status = 'pending'`,
    ).bind(id),
  ]);
  return json(request, env, { ok: true, status });
}

function validateSubmission(body) {
  const lat = boundedNumber(body.lat, 'Широта', 40.45, 55.55);
  const lng = boundedNumber(body.lng, 'Долгота', 46.45, 87.4);
  const username = safeUserText(body.username, 'Имя', 2, 30);
  const placeKind = requiredText(body.placeKind, 'Категория', 2, 40);
  if (!PLACE_KINDS.has(placeKind)) throw new HttpError(400, 'Неизвестная категория');
  const name = optionalSafeText(body.name, 'Название', 80);
  if (['cafe', 'fuel', 'organization'].includes(placeKind) && !name) {
    throw new HttpError(400, 'Укажи название места');
  }
  if (typeof body.isFree !== 'boolean') throw new HttpError(400, 'Укажи стоимость');
  const cleanliness = boundedInteger(body.cleanliness, 'Чистота', 1, 5);
  const condition = requiredText(body.condition, 'Состояние', 2, 20);
  if (!CONDITIONS.has(condition)) throw new HttpError(400, 'Неизвестное состояние');
  const accessType = requiredText(body.accessType, 'Доступ', 2, 20);
  if (!ACCESS_TYPES.has(accessType)) throw new HttpError(400, 'Неизвестный тип доступа');
  for (const field of [
    'hasPaper', 'hasSoap', 'wheelchairAccessible', 'phoneCharging',
  ]) {
    if (body[field] !== null && body[field] !== undefined && typeof body[field] !== 'boolean') {
      throw new HttpError(400, 'Некорректные параметры места');
    }
  }
  const comment = optionalSafeText(body.comment, 'Комментарий', 300);
  const deviceKey = body.deviceKey === null || body.deviceKey === undefined
    ? null
    : requiredText(body.deviceKey, 'Ключ устройства', 12, 80);
  return {
    lat,
    lng,
    username,
    placeKind,
    name,
    isFree: body.isFree,
    cleanliness,
    condition,
    hasPaper: body.hasPaper,
    hasSoap: body.hasSoap,
    wheelchairAccessible: body.wheelchairAccessible,
    phoneCharging: body.phoneCharging,
    accessType,
    deviceKey,
    comment,
  };
}

function validateReport(body) {
  const placeKey = requiredText(body.placeKey, 'Точка', 3, 120);
  const lat = boundedNumber(body.lat, 'Широта', -90, 90);
  const lng = boundedNumber(body.lng, 'Долгота', -180, 180);
  const username = safeUserText(body.username, 'Имя', 2, 30);
  const cleanliness = boundedInteger(body.cleanliness, 'Чистота', 1, 5);
  const condition = requiredText(body.condition, 'Состояние', 2, 20);
  if (!CONDITIONS.has(condition)) throw new HttpError(400, 'Неизвестное состояние');
  const accessType = requiredText(body.accessType, 'Доступ', 2, 20);
  if (!ACCESS_TYPES.has(accessType)) throw new HttpError(400, 'Неизвестный тип доступа');
  const nullableBooleans = [
    'isFree', 'hasToilet', 'hasPaper', 'hasSoap', 'wheelchairAccessible',
    'phoneCharging',
  ];
  for (const field of nullableBooleans) {
    if (body[field] !== null && body[field] !== undefined && typeof body[field] !== 'boolean') {
      throw new HttpError(400, 'Некорректные параметры отзыва');
    }
  }
  return {
    ...body,
    placeKey,
    lat,
    lng,
    username,
    cleanliness,
    condition,
    accessType,
    comment: optionalSafeText(body.comment, 'Комментарий', 300),
  };
}

function validateLocationCorrection(body) {
  const placeKey = requiredText(body.placeKey, 'Точка', 3, 120);
  const currentLat = boundedNumber(body.currentLat, 'Текущая широта', 40.45, 55.55);
  const currentLng = boundedNumber(body.currentLng, 'Текущая долгота', 46.45, 87.4);
  const proposedLat = boundedNumber(body.proposedLat, 'Новая широта', 40.45, 55.55);
  const proposedLng = boundedNumber(body.proposedLng, 'Новая долгота', 46.45, 87.4);
  const username = safeUserText(body.username, 'Имя', 2, 30);
  const comment = optionalSafeText(body.comment, 'Комментарий', 300);

  if (
    Math.abs(currentLat - proposedLat) < 0.000001 &&
    Math.abs(currentLng - proposedLng) < 0.000001
  ) {
    throw new HttpError(400, 'Передвинь метку в новое место');
  }

  return {
    placeKey,
    currentLat,
    currentLng,
    proposedLat,
    proposedLng,
    username,
    comment,
  };
}

async function enforceRateLimit(request, env, scope, limit, windowSeconds) {
  const ip = request.headers.get('cf-connecting-ip') || 'unknown';
  const salt = env.RATE_LIMIT_SALT || 'tmaps-local-development';
  const bucketKey = await sha256(`${salt}|${scope}|${ip}`);
  const windowStart = Math.floor(Date.now() / 1000 / windowSeconds) * windowSeconds;
  const row = await env.DB.prepare(
    `INSERT INTO rate_limits (bucket_key, window_start, hits)
     VALUES (?, ?, 1)
     ON CONFLICT (bucket_key, window_start) DO UPDATE SET hits = hits + 1
     RETURNING hits`,
  ).bind(bucketKey, windowStart).first();
  if (Number(row.hits) > limit) {
    throw new HttpError(429, 'Слишком много действий. Попробуй немного позже');
  }

  if (Math.random() < 0.02) {
    await env.DB.prepare(
      'DELETE FROM rate_limits WHERE window_start < ?',
    ).bind(windowStart - 172800).run();
  }
}

async function verifyTurnstile(token, request, env) {
  if (!env.TURNSTILE_SECRET) return;
  if (typeof token !== 'string' || token.length < 10) {
    throw new HttpError(400, 'Подтверди, что ты не робот');
  }
  const form = new FormData();
  form.set('secret', env.TURNSTILE_SECRET);
  form.set('response', token);
  const ip = request.headers.get('cf-connecting-ip');
  if (ip) form.set('remoteip', ip);
  const response = await fetch(
    'https://challenges.cloudflare.com/turnstile/v0/siteverify',
    { method: 'POST', body: form },
  );
  const result = await response.json();
  if (!result.success) throw new HttpError(400, 'Проверка защиты не пройдена');
}

function requireAdmin(request, env) {
  if (!env.ADMIN_TOKEN) throw new HttpError(503, 'Админ-доступ ещё не настроен');
  if (request.headers.get('authorization') !== `Bearer ${env.ADMIN_TOKEN}`) {
    throw new HttpError(401, 'Нужен админ-доступ');
  }
}

async function readJson(request) {
  const contentLength = Number(request.headers.get('content-length') || 0);
  if (contentLength > 20_000) throw new HttpError(413, 'Запрос слишком большой');
  try {
    const body = await request.json();
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error();
    return body;
  } catch {
    throw new HttpError(400, 'Неверный формат запроса');
  }
}

function safeUserText(value, label, min, max) {
  const text = requiredText(value, label, min, max);
  if (CONTROL_PATTERN.test(text) || /[\r\n\t]/.test(text)) {
    throw new HttpError(400, `${label} содержит недопустимые символы`);
  }
  if (URL_PATTERN.test(text)) throw new HttpError(400, 'Ссылки запрещены');
  if (hasBlockedContent(text)) throw new HttpError(400, 'Удали оскорбления или опасный текст');
  return text;
}

function optionalSafeText(value, label, max) {
  if (value === null || value === undefined || String(value).trim() === '') return null;
  return safeUserText(String(value), label, 1, max);
}

function requiredText(value, label, min, max) {
  if (typeof value !== 'string') throw new HttpError(400, `${label}: неверное значение`);
  const text = value.trim();
  if (text.length < min || text.length > max) {
    throw new HttpError(400, `${label}: допустимо от ${min} до ${max} символов`);
  }
  return text;
}

function boundedNumber(value, label, min, max) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) {
    throw new HttpError(400, `${label}: неверное значение`);
  }
  return value;
}

function boundedInteger(value, label, min, max) {
  if (!Number.isInteger(value) || value < min || value > max) {
    throw new HttpError(400, `${label}: неверное значение`);
  }
  return value;
}

function hasBlockedContent(value) {
  const normalized = value.toLowerCase().replaceAll('ё', 'е');
  return BLOCKED_FRAGMENTS.some((fragment) => normalized.includes(fragment));
}

function allowedOrigins(env) {
  const configured = String(env.ALLOWED_ORIGINS || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
  return configured.length ? configured : DEFAULT_ORIGINS;
}

function isAllowedOrigin(request, env) {
  const origin = request.headers.get('origin');
  return !origin || allowedOrigins(env).includes(origin);
}

function corsHeaders(request, env) {
  const headers = {
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Allow-Methods': 'GET, POST, PATCH, OPTIONS',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  };
  const origin = request.headers.get('origin');
  if (origin && allowedOrigins(env).includes(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
  }
  return headers;
}

function json(request, env, payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      ...corsHeaders(request, env),
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

function normalizeRows(rows) {
  return rows.map(normalizeRow);
}

function normalizeRow(row) {
  const result = { ...row };
  for (const key of [
    'is_free', 'has_toilet', 'has_paper', 'has_soap',
    'wheelchair_accessible', 'phone_charging', 'is_current',
  ]) {
    if (key in result && result[key] !== null) result[key] = result[key] === 1;
  }
  return result;
}

function boolInt(value) {
  return value ? 1 : 0;
}

function nullableBoolInt(value) {
  return value === null || value === undefined ? null : boolInt(value);
}

async function sha256(value) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
}

export const testing = {
  HttpError,
  validateSubmission,
  validateReport,
  validateLocationCorrection,
  normalizeRow,
  isAllowedOrigin,
};
