import 'ha.dart';
import 'project.dart';

/// One address field of a card and the function of the entity that it follows (the function and "cmd" for its command
/// address or "status" for its status address).
class CardSlot {
  const CardSlot(this.attr, this.role);
  final String attr, role;
}

const _onoffCmd = CardSlot('onoff', 'cmd'), _onoffSt = CardSlot('onoff', 'status');

/// What a card takes from an entity of Home Assistant: the domains it accepts and what each address field of the card
/// follows.
class CardEntityDef {
  const CardEntityDef(this.domains, this.slots, {this.byDomain = const {}});
  final List<String> domains;
  final Map<String, CardSlot> slots;

  /// For some domains a field follows another function (a binary sensor has an on/off status, not a number).
  final Map<String, Map<String, CardSlot>> byDomain;

  CardSlot? slot(String key, String domain) => byDomain[domain]?[key] ?? slots[key];
}

/// The cards that can take an entity. A field that the card does not show (a card setting turns it off) is not used.
const Map<String, CardEntityDef> kCardEntity = {
  'switch': CardEntityDef(['light', 'switch', 'fan', 'input_boolean', 'automation', 'script', 'scene'], {'write': _onoffCmd, 'status': _onoffSt}),
  'button': CardEntityDef(['scene', 'script', 'automation', 'light', 'switch', 'fan', 'input_boolean', 'media_player', 'remote'], {'write': _onoffCmd}),
  'scene': CardEntityDef(['scene', 'script', 'automation'], {'write': _onoffCmd}),
  'value': CardEntityDef([
    'sensor',
    'binary_sensor'
  ], {
    'status': CardSlot('sensor', 'status')
  }, byDomain: {
    'binary_sensor': {'status': CardSlot('binary', 'status')},
  }),
  'dimmer': CardEntityDef([
    'light'
  ], {
    'write': _onoffCmd,
    'value': CardSlot('brightness', 'cmd'),
    'status': CardSlot('brightness', 'status'),
    'ctWrite': CardSlot('colortemp', 'cmd'),
    'ctStatus': CardSlot('colortemp', 'status'),
  }),
  'shutter': CardEntityDef([
    'cover'
  ], {
    'upDown': CardSlot('move', 'cmd'),
    'stop': CardSlot('stop', 'cmd'),
    'position': CardSlot('position', 'cmd'),
    'status': CardSlot('position', 'status'),
  }),
  'ac': CardEntityDef([
    'climate'
  ], {
    'power': _onoffCmd,
    'powerSt': _onoffSt,
    'setpoint': CardSlot('setpoint', 'cmd'),
    'setpointSt': CardSlot('setpoint', 'status'),
    'current': CardSlot('current', 'status'),
    'mode': CardSlot('mode', 'cmd'),
    'modeSt': CardSlot('mode', 'status'),
  }),
};

final _entityId = RegExp(r'^[a-z0-9_]+\.[a-z0-9_]+$');

/// The entity of Home Assistant that a card refers to, whatever the kind of card ('' = none): the entity it follows, the
/// media player of a media player card, the remote of a remote control card.
String widgetEntity(Json w) {
  if (mediaIsKnx(w)) return '';
  final e = cardEntity(w);
  if (e.isNotEmpty) return e;
  if (w['type'] == 'media') return (jsonMap(w['media'])['entity'] ?? '').toString().trim();
  if (w['type'] == 'remote') return (jsonMap(w['remote'])['entity'] ?? '').toString().trim();
  return '';
}

/// Changes the source of a media player card: 'knx' (addresses) or 'ha' (a media player of Home Assistant). What belongs
/// to the other source is forgotten. False when the card already has that source.
bool switchMediaSource(Json w, String source) {
  if (w['type'] != 'media' || mediaIsKnx(w) == (source == 'knx')) return false;
  if (source == 'knx') {
    w['source'] = 'knx';
    final m = jsonMap(w['media']);
    m['entity'] = '';
    w['media'] = m;
  } else {
    w.remove('source');
    w['bind'] = <String, dynamic>{};
  }
  return true;
}

/// The entity a card follows ('' = none).
String cardEntity(Json w) => w['ha'] is Map ? ((w['ha'] as Map)['entity'] ?? '').toString() : '';

/// A push button that follows a media player or a remote: it calls a service of Home Assistant directly (a command and its
/// parameters), it has no address.
bool haDirect(Json w) => w['type'] == 'button' && const ['media_player', 'remote'].contains(cardEntity(w).split('.').first);

/// Whether a card takes its address fields from Home Assistant (an entity is chosen, or the HA button was pressed).
bool cardIsHa(Json w) => cardEntity(w).isNotEmpty || w['source'] == 'ha';

/// Why [entityId] does not suit the card [w] (null = it does).
String? cardEntityProblem(Json w, String entityId) {
  final type = (w['type'] ?? '').toString();
  final def = kCardEntity[type];
  if (def == null) return 'This card cannot take an entity yet.';
  final id = entityId.trim();
  if (!_entityId.hasMatch(id)) return 'The entity must look like light.living_room.';
  if (!def.domains.contains(id.split('.').first)) return 'A ${kWidgetTypes[type]?.name ?? type} card takes: ${def.domains.join(', ')}.';
  return null;
}

/// Makes the card follow [entityId] directly: nothing is added to the project, the card only keeps the entity, and the
/// App and the Editor give it its addresses when they run. The KNX addresses of the card are forgotten. An error text,
/// or null.
String? setCardEntity(Json w, String entityId) {
  final err = cardEntityProblem(w, entityId);
  if (err != null) return err;
  // The KNX addresses of the card are forgotten.
  w['bind'] = <String, dynamic>{};
  w['ha'] = <String, dynamic>{'entity': entityId.trim()};
  w['source'] = 'ha';
  return null;
}

/// Changes the source of the address fields: 'ha' forgets the KNX addresses of the card, 'knx' forgets the entity.
/// Nothing of the other side is kept. False when the card already has that source.
bool switchCardSource(Json w, String source) {
  final def = kCardEntity[(w['type'] ?? '').toString()];
  if (def == null || cardIsHa(w) == (source == 'ha')) return false;
  if (source == 'ha') {
    w['bind'] = <String, dynamic>{};
    w['source'] = 'ha';
  } else {
    w.remove('ha');
    w.remove('source');
  }
  return true;
}

/// The addresses that the cards get from the entities they follow, made when the project is shown or run (they are
/// not stored in the project and are not shown in the Editor).
class CardEntities {
  CardEntities(this.gas, this.binds);

  /// The virtual addresses (several cards that follow one entity share them).
  final List<Json> gas;

  /// For each card (by id): the address fields to fill, field → id of an address.
  final Map<String, Map<String, dynamic>> binds;
}

CardEntities cardEntities(Json doc) {
  final gas = <Json>[];
  final byKey = <String, Json>{};
  final binds = <String, Map<String, dynamic>>{};
  for (final w in allWidgets(doc)) {
    final id = cardEntity(w);
    final def = kCardEntity[(w['type'] ?? '').toString()];
    if (id.isEmpty || def == null || haDirect(w) || cardEntityProblem(w, id) != null) continue;
    final shown = {for (final sl in slotsFor(w)) sl.key};
    final mine = <String, dynamic>{};
    for (final f in def.slots.keys) {
      if (!shown.contains(f)) continue;
      final slot = def.slot(f, id.split('.').first);
      final attr = slot == null ? null : haAttr(slot.attr);
      if (slot == null || attr == null) continue;
      final key = '$id|${slot.attr}|${slot.role}';
      var ga = byKey[key];
      if (ga == null) {
        // An address of a reserved main group (1000), so that it never meets a real or an older virtual address.
        final i = gas.length;
        ga = byKey[key] = {
          'id': 'hac_$key',
          'address': '1000/${i ~/ 250}/${i % 250 + 1}',
          'name': '$id (${slot.role == 'cmd' ? 'command' : 'status'})',
          'dpt': attr.dpt,
          'ha': {'entity': id, 'attr': slot.attr, 'role': slot.role, 'card': true},
        };
        gas.add(ga);
      }
      mine[f] = ga['id'];
    }
    binds[w['id'].toString()] = mine;
  }
  return CardEntities(gas, binds);
}

/// Gives the cards that follow an entity their addresses, in place (used by the App on the configuration it loads; the
/// stored project is not changed).
void applyCardEntities(Json doc) {
  final list = (doc['groupAddresses'] = List<dynamic>.from(doc['groupAddresses'] as List? ?? const []));
  list.removeWhere((g) => g is Map && g['ha'] is Map && (g['ha'] as Map)['card'] == true);
  final ce = cardEntities(doc);
  list.addAll(ce.gas);
  for (final w in allWidgets(doc)) {
    final b = ce.binds[w['id'].toString()];
    if (b == null) continue;
    final bind = jsonMap(w['bind']);
    bind.addAll(b);
    w['bind'] = bind;
  }
}
