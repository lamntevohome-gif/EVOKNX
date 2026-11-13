import 'ha.dart';
import 'project.dart';

/// What a card takes from an entity of Home Assistant: the domains it accepts, the function of the entity it follows
/// and which address field of the card each address goes to ("cmd" = the command address, "status" = the status one).
class CardEntityDef {
  const CardEntityDef(this.domains, this.attr, this.slots);
  final List<String> domains;
  final String attr;
  final Map<String, String> slots;
}

/// The cards that can take an entity (more are added later).
const Map<String, CardEntityDef> kCardEntity = {
  'switch': CardEntityDef(['light', 'switch', 'fan', 'input_boolean', 'automation', 'script', 'scene'], 'onoff', {'write': 'cmd', 'status': 'status'}),
  'button': CardEntityDef(['scene', 'script', 'automation', 'light', 'switch', 'fan', 'input_boolean'], 'onoff', {'write': 'cmd'}),
  'scene': CardEntityDef(['scene', 'script', 'automation'], 'onoff', {'write': 'cmd'}),
  'value': CardEntityDef(['sensor'], 'sensor', {'status': 'status'}),
};

final _entityId = RegExp(r'^[a-z0-9_]+\.[a-z0-9_]+$');

/// Makes the card follow [entityId]. The virtual addresses of the entity are added to the Extensions tab when they
/// are not there yet (in the room of Extensions where the entity already is, or in one named like the room of the
/// card), and the address fields of the card are filled with them. The card then uses the entity, not the addresses
/// that were typed. An error text, or null.
String? bindCardEntity(Json doc, Json w, String roomTitle, String entityId, {HaEntity? known}) {
  final type = (w['type'] ?? '').toString();
  final def = kCardEntity[type];
  if (def == null) return 'This card cannot take an entity yet.';
  final id = entityId.trim();
  if (!_entityId.hasMatch(id)) return 'The entity must look like light.living_room.';
  final domain = id.split('.').first;
  if (!def.domains.contains(domain)) return 'A ${kWidgetTypes[type]?.name ?? type} card takes: ${def.domains.join(', ')}.';
  final e = known ?? HaEntity(id, '', {});
  unbindCardEntity(doc, w);
  var rid = haEntityRoom(doc, id);
  if (rid == null) {
    final name = roomTitle.trim().isEmpty ? 'Rooms' : roomTitle.trim();
    Json? room;
    for (final r in haRooms(doc)) {
      if (r['name'] == name) room = r;
    }
    room ??= addHaRoom(doc, name, haNextMain(doc));
    rid = room['id'] as String;
  }
  try {
    addHaEntity(doc, e, [def.attr], roomId: rid);
  } on StateError catch (x) {
    return x.message;
  }
  final bind = jsonMap(w['bind']);
  for (final s in def.slots.entries) {
    Json? ga;
    for (final g in jsonList(doc['groupAddresses'])) {
      final h = g['ha'];
      if (h is Map && h['entity'] == id && h['attr'] == def.attr && h['role'] == s.value) ga = g;
    }
    if (ga == null) {
      bind.remove(s.key);
    } else {
      bind[s.key] = ga['id'];
    }
  }
  w['bind'] = bind;
  w['ha'] = {'entity': id};
  return null;
}

/// The card stops following its entity: its address fields are emptied (the addresses stay in the Extensions tab).
void unbindCardEntity(Json doc, Json w) {
  if (w['ha'] is! Map) return;
  final def = kCardEntity[(w['type'] ?? '').toString()];
  if (def != null) {
    final bind = jsonMap(w['bind']);
    for (final k in def.slots.keys) {
      bind.remove(k);
    }
    w['bind'] = bind;
  }
  w.remove('ha');
}

/// Whether a card takes its address fields from Home Assistant (an entity is chosen, or the HA button was pressed).
bool cardIsHa(Json w) => cardEntity(w).isNotEmpty || w['source'] == 'ha';

/// Changes the source of the address fields: 'ha' forgets the KNX addresses of the card, 'knx' forgets the entity and
/// its addresses. Nothing of the other side is kept. False when the card already has that source.
bool switchCardSource(Json doc, Json w, String source) {
  final def = kCardEntity[(w['type'] ?? '').toString()];
  if (def == null || cardIsHa(w) == (source == 'ha')) return false;
  if (source == 'ha') {
    final bind = jsonMap(w['bind']);
    for (final k in def.slots.keys) {
      bind.remove(k);
    }
    w['bind'] = bind;
    w['source'] = 'ha';
  } else {
    unbindCardEntity(doc, w);
    w.remove('source');
  }
  return true;
}

/// The entity a card follows ('' = none).
String cardEntity(Json w) => w['ha'] is Map ? ((w['ha'] as Map)['entity'] ?? '').toString() : '';
