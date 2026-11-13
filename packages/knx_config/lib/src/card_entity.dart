import 'ha.dart';
import 'project.dart';

/// What a card takes from an entity of Home Assistant: the domains it accepts, the function of the entity it follows
/// and which address field of the card each address of the function goes to ("cmd" = the command address, "status" =
/// the status one).
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

/// The entity a card follows ('' = none).
String cardEntity(Json w) => w['ha'] is Map ? ((w['ha'] as Map)['entity'] ?? '').toString() : '';

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
  final def = kCardEntity[(w['type'] ?? '').toString()]!;
  final bind = jsonMap(w['bind']);
  for (final k in def.slots.keys) {
    bind.remove(k);
  }
  w['bind'] = bind;
  w['ha'] = {'entity': entityId.trim()};
  w['source'] = 'ha';
  return null;
}

/// Changes the source of the address fields: 'ha' forgets the KNX addresses of the card, 'knx' forgets the entity.
/// Nothing of the other side is kept. False when the card already has that source.
bool switchCardSource(Json w, String source) {
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
    w.remove('ha');
    w.remove('source');
  }
  return true;
}

/// The addresses that the cards get from the entities they follow, made when the project is shown or run (they are
/// not stored in the project and are not in the Extensions tab).
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
    if (id.isEmpty || def == null || cardEntityProblem(w, id) != null) continue;
    final attr = haAttr(def.attr)!;
    final mine = <String, dynamic>{};
    for (final s in def.slots.entries) {
      final key = '$id|${def.attr}|${s.value}';
      var ga = byKey[key];
      if (ga == null) {
        // An address of a reserved main group (1000), so that it never meets a real or an Extensions address.
        final i = gas.length;
        ga = byKey[key] = {
          'id': 'hac_$id|${def.attr}|${s.value}',
          'address': '1000/${i ~/ 250}/${i % 250 + 1}',
          'name': '$id (${s.value == 'cmd' ? 'command' : 'status'})',
          'dpt': attr.dpt,
          'ha': {'entity': id, 'attr': def.attr, 'role': s.value == 'cmd' ? 'cmd' : 'status', 'card': true},
        };
        gas.add(ga);
      }
      mine[s.key] = ga['id'];
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
