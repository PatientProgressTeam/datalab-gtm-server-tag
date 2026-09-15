___INFO___

{
  "type": "TAG",
  "id": "cvt_temp_public_id",
  "version": 1,
  "securityGroups": [],
  "displayName": "DataLab Studio",
  "brand": {
    "id": "brand_dummy",
    "displayName": "DataLab Studio"
  },
  "description": "Send server-side events to DataLab Studio for identity resolution, attribution and conversion delivery to ad platforms.",
  "containerContexts": [
    "SERVER"
  ]
}


___TEMPLATE_PARAMETERS___

[
  {
    "type": "TEXT",
    "name": "endpoint",
    "displayName": "Endpoint URL",
    "simpleValueType": true,
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      },
      {
        "type": "REGEX",
        "args": [
          "^https://.*"
        ],
        "errorMessage": "The endpoint must be an https:// URL."
      }
    ],
    "defaultValue": "https://app.datalabstudio.io/s2s",
    "help": "Your DataLab Studio ingestion endpoint. Found under Setup \u003e Server keys."
  },
  {
    "type": "TEXT",
    "name": "serverKey",
    "displayName": "Server key",
    "simpleValueType": true,
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      }
    ],
    "help": "A server key from Setup \u003e Server keys in DataLab Studio. This is a secret and is different from the public write key in your website tag."
  },
  {
    "type": "SELECT",
    "name": "eventNameSource",
    "displayName": "Event name",
    "macrosInSelect": false,
    "selectItems": [
      {
        "value": "fromEvent",
        "displayValue": "Use the incoming event name"
      },
      {
        "value": "custom",
        "displayValue": "Set it manually"
      }
    ],
    "simpleValueType": true,
    "defaultValue": "fromEvent"
  },
  {
    "type": "TEXT",
    "name": "customEventName",
    "displayName": "Event name",
    "simpleValueType": true,
    "enablingConditions": [
      {
        "paramName": "eventNameSource",
        "paramValue": "custom",
        "type": "EQUALS"
      }
    ],
    "valueValidators": [
      {
        "type": "NON_EMPTY"
      }
    ]
  },
  {
    "type": "GROUP",
    "name": "identityGroup",
    "displayName": "Identity",
    "groupStyle": "ZIPPY_OPEN",
    "subParams": [
      {
        "type": "LABEL",
        "name": "identityNote",
        "displayName": "An event with no email, phone, user ID or click identifier is stored but cannot be matched to a person, or to the advertising that produced them. These fields default to the standard locations in the incoming event data."
      },
      {
        "type": "TEXT",
        "name": "email",
        "displayName": "Email",
        "simpleValueType": true,
        "help": "Leave blank to read user_data.email_address from the event."
      },
      {
        "type": "TEXT",
        "name": "phone",
        "displayName": "Phone",
        "simpleValueType": true,
        "help": "Leave blank to read user_data.phone_number from the event."
      },
      {
        "type": "TEXT",
        "name": "userId",
        "displayName": "User ID",
        "simpleValueType": true,
        "help": "Leave blank to read user_id from the event."
      }
    ]
  },
  {
    "type": "GROUP",
    "name": "consentGroup",
    "displayName": "Consent",
    "groupStyle": "ZIPPY_OPEN",
    "subParams": [
      {
        "type": "SELECT",
        "name": "consentMode",
        "displayName": "Advertising consent",
        "macrosInSelect": false,
        "selectItems": [
          {
            "value": "fromEvent",
            "displayValue": "Read from the incoming event"
          },
          {
            "value": "granted",
            "displayValue": "Always granted"
          },
          {
            "value": "denied",
            "displayValue": "Always denied"
          }
        ],
        "simpleValueType": true,
        "defaultValue": "fromEvent"
      },
      {
        "type": "LABEL",
        "name": "consentNote",
        "displayName": "Events without advertising consent are stored and reported, but are not forwarded to ad platforms. If consent cannot be determined it is treated as denied — assuming permission that was never granted is the one error here with legal weight."
      }
    ]
  },
  {
    "type": "GROUP",
    "name": "advancedGroup",
    "displayName": "Advanced",
    "groupStyle": "ZIPPY_CLOSED",
    "subParams": [
      {
        "type": "CHECKBOX",
        "name": "sendAllEventData",
        "checkboxText": "Include all event data",
        "simpleValueType": true,
        "defaultValue": false,
        "help": "Forwards every field in the incoming event, not just the mapped ones. Useful when you need a property DataLab does not map by default."
      },
      {
        "type": "SIMPLE_TABLE",
        "name": "extraProperties",
        "displayName": "Additional properties",
        "simpleTableColumns": [
          {
            "defaultValue": "",
            "displayName": "Name",
            "name": "name",
            "type": "TEXT",
            "isUnique": true
          },
          {
            "defaultValue": "",
            "displayName": "Value",
            "name": "value",
            "type": "TEXT"
          }
        ],
        "newRowButtonText": "Add property"
      },
      {
        "type": "CHECKBOX",
        "name": "logResponse",
        "checkboxText": "Log the response when previewing",
        "simpleValueType": true,
        "defaultValue": true,
        "help": "DataLab returns warnings when events arrive without identity or consent. Leave this on while you are setting the tag up."
      }
    ]
  }
]


___SANDBOXED_JS_FOR_SERVER___

// DataLab Studio — server-side tag
//
// Forwards one event to a DataLab Studio workspace. Identity resolution,
// attribution and delivery to ad platforms all happen there; this tag's only
// job is to hand over a well-formed payload and report honestly on what came
// back.
//
// WHY THE RESPONSE IS SURFACED RATHER THAN SWALLOWED
// A container configured with a field mapped wrongly will send events happily
// for months, and the person who configured it is the only one who can fix it.
// DataLab returns warnings — events with no identity, events without consent —
// and this tag logs them during preview rather than returning a silent success.

const getAllEventData = require('getAllEventData');
const sendHttpRequest = require('sendHttpRequest');
const getTimestampMillis = require('getTimestampMillis');
const getType = require('getType');
const JSON = require('JSON');
const makeString = require('makeString');
const makeNumber = require('makeNumber');
const logToConsole = require('logToConsole');

const eventData = getAllEventData();

function pick(explicit, path) {
  if (explicit) return explicit;
  let node = eventData;
  const parts = path.split('.');
  for (let i = 0; i < parts.length; i++) {
    if (getType(node) !== 'object') return undefined;
    node = node[parts[i]];
  }
  return node;
}

// Click identifiers are the strongest match signal an ad platform can receive,
// and they arrive in several places depending on how the client-side tag was
// set up. Checked in order of reliability rather than assuming one shape.
function collectClickIds() {
  const ids = {};
  const keys = ['gclid', 'gbraid', 'wbraid', 'fbclid', 'ttclid', 'msclkid'];
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    const v = eventData[k]
      || (eventData.attribution ? eventData.attribution[k] : undefined)
      || (eventData.user_data ? eventData.user_data[k] : undefined);
    if (v) ids[k] = makeString(v);
  }
  return ids;
}

function collectUtm() {
  const utm = {};
  const keys = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term'];
  for (let i = 0; i < keys.length; i++) {
    const v = eventData[keys[i]];
    if (v) utm[keys[i]] = makeString(v);
  }
  return utm;
}

// Consent defaults to denied when it cannot be determined. Forwarding an event
// to an ad platform on an assumption about permission is the one mistake here
// that carries legal consequence rather than merely statistical.
function resolveAdConsent() {
  if (data.consentMode === 'granted') return true;
  if (data.consentMode === 'denied') return false;
  const c = eventData.consent || {};
  const state = c.ad_user_data || c.ad_storage || c.ad;
  if (state === true || state === 'granted' || state === 'GRANTED') return true;
  return false;
}

function resolveAnalyticsConsent() {
  if (data.consentMode === 'granted') return true;
  if (data.consentMode === 'denied') return false;
  const c = eventData.consent || {};
  const state = c.analytics_storage || c.analytics;
  if (state === true || state === 'granted' || state === 'GRANTED') return true;
  return false;
}

const ecom = eventData.ecommerce || {};

const properties = {};
if (data.sendAllEventData === true) {
  for (const key in eventData) {
    if (key !== 'user_data' && key !== 'consent') properties[key] = eventData[key];
  }
}
if (ecom.value !== undefined) properties.value = makeNumber(ecom.value);
if (eventData.value !== undefined && properties.value === undefined) {
  properties.value = makeNumber(eventData.value);
}
if (ecom.currency) properties.currency = makeString(ecom.currency);
if (ecom.transaction_id) properties.order_id = makeString(ecom.transaction_id);
if (ecom.items) properties.items = ecom.items;
if (eventData.page_location) properties.path = makeString(eventData.page_location);

const extra = data.extraProperties || [];
for (let i = 0; i < extra.length; i++) {
  if (extra[i].name) properties[extra[i].name] = extra[i].value;
}

const payload = {
  events: [{
    event_name: data.eventNameSource === 'custom'
      ? data.customEventName
      : makeString(eventData.event_name || 'unknown'),
    ts: getTimestampMillis(),
    user_data: {
      email_address: pick(data.email, 'user_data.email_address'),
      phone_number: pick(data.phone, 'user_data.phone_number'),
      first_name: pick(null, 'user_data.address.first_name'),
      last_name: pick(null, 'user_data.address.last_name')
    },
    user_id: pick(data.userId, 'user_id'),
    client_id: eventData.client_id,
    properties: properties,
    attribution: {
      utm: collectUtm(),
      clickIds: collectClickIds()
    },
    consent: {
      ad: resolveAdConsent(),
      analytics: resolveAnalyticsConsent()
    }
  }]
};

const options = {
  headers: {
    'content-type': 'application/json',
    'x-datalab-key': data.serverKey
  },
  method: 'POST',
  timeout: 5000
};

sendHttpRequest(data.endpoint, options, JSON.stringify(payload)).then((result) => {
  if (data.logResponse === true) {
    logToConsole('DataLab Studio: HTTP ' + result.statusCode);
    // Warnings are the point. DataLab reports events that arrived without an
    // identifier or without consent, and a container that is dropping either
    // will otherwise look like it is working.
    if (result.body) logToConsole('DataLab Studio: ' + result.body);
  }
  if (result.statusCode >= 200 && result.statusCode < 300) {
    data.gtmOnSuccess();
  } else {
    data.gtmOnFailure();
  }
}).catch(() => {
  if (data.logResponse === true) {
    logToConsole('DataLab Studio: request failed to reach ' + data.endpoint);
  }
  data.gtmOnFailure();
});


___SERVER_PERMISSIONS___

[
  {
    "instance": {
      "key": {
        "publicId": "read_event_data",
        "versionId": "1"
      },
      "param": [
        {
          "key": "eventDataAccess",
          "value": {
            "type": 1,
            "string": "any"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "send_http",
        "versionId": "1"
      },
      "param": [
        {
          "key": "allowedUrls",
          "value": {
            "type": 1,
            "string": "any"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  },
  {
    "instance": {
      "key": {
        "publicId": "logging",
        "versionId": "1"
      },
      "param": [
        {
          "key": "environments",
          "value": {
            "type": 1,
            "string": "debug"
          }
        }
      ]
    },
    "clientAnnotations": {
      "isEditedByUser": true
    },
    "isRequired": true
  }
]


___TESTS___

scenarios:
- name: Sends a purchase with identity and consent
  code: |-
    const mockData = {
      endpoint: 'https://app.datalabstudio.io/s2s',
      serverKey: 'dls_test',
      eventNameSource: 'fromEvent',
      consentMode: 'fromEvent',
      logResponse: false
    };
    mock('getAllEventData', () => ({
      event_name: 'purchase',
      user_data: { email_address: 'buyer@example.com' },
      ecommerce: { value: 199.97, currency: 'USD', transaction_id: 'ord_1' },
      consent: { ad_user_data: 'granted', analytics_storage: 'granted' },
      gclid: 'TEST_GCLID'
    }));
    let sent;
    mock('sendHttpRequest', (url, options, body) => {
      sent = JSON.parse(body);
      return Promise.create((resolve) => resolve({ statusCode: 200, body: '{"ok":true}' }));
    });
    runCode(mockData);
    const e = sent.events[0];
    assertThat(e.event_name).isEqualTo('purchase');
    assertThat(e.user_data.email_address).isEqualTo('buyer@example.com');
    assertThat(e.properties.value).isEqualTo(199.97);
    assertThat(e.attribution.clickIds.gclid).isEqualTo('TEST_GCLID');
    assertThat(e.consent.ad).isEqualTo(true);
    assertApi('gtmOnSuccess').wasCalled();
- name: Treats missing consent as denied
  code: |-
    const mockData = {
      endpoint: 'https://app.datalabstudio.io/s2s',
      serverKey: 'dls_test',
      eventNameSource: 'fromEvent',
      consentMode: 'fromEvent',
      logResponse: false
    };
    mock('getAllEventData', () => ({
      event_name: 'purchase',
      user_data: { email_address: 'buyer@example.com' }
    }));
    let sent;
    mock('sendHttpRequest', (url, options, body) => {
      sent = JSON.parse(body);
      return Promise.create((resolve) => resolve({ statusCode: 200, body: '{"ok":true}' }));
    });
    runCode(mockData);
    assertThat(sent.events[0].consent.ad).isEqualTo(false);
- name: Reports failure on a non-2xx response
  code: |-
    const mockData = {
      endpoint: 'https://app.datalabstudio.io/s2s',
      serverKey: 'bad_key',
      eventNameSource: 'fromEvent',
      consentMode: 'granted',
      logResponse: false
    };
    mock('getAllEventData', () => ({ event_name: 'lead' }));
    mock('sendHttpRequest', () =>
      Promise.create((resolve) => resolve({ statusCode: 401, body: '{"ok":false}' })));
    runCode(mockData);
    assertApi('gtmOnFailure').wasCalled();


___TERMS_OF_SERVICE___

By using this template you agree to the DataLab Studio terms of service at https://app.datalabstudio.io/terms and the privacy policy at https://app.datalabstudio.io/privacy. This template sends event data you configure to a DataLab Studio workspace you control, using a server key you supply. It sends data to no other destination.


___NOTES___

Created on 14/09/2026
