class_name HeroData
## The hero roster. Identity, faction, role, rarity and art brief are set by the lead
## designer; base_stats / ultimate / passives are owned by the core-logic agent.
## Keys are part of the contract in docs/dev/architecture.md. Ids never change.

const ROSTER: Array[Dictionary] = [
	# ---------------- CELESTIAL (gold, ivory, sky blue) ----------------
	{
		"id": "seraphiel", "name": "Seraphiel", "title": "the Choir Eternal",
		"faction": "celestial", "role": "caster", "rarity": "legendary",
		"bio": "The last seraph who still sings the hymn that once held the sky together. Every note is a sunrise; every chorus, a judgment.",
		"look": "Six-winged seraph (two pairs large, one small pair at the head). Long flowing platinum-blonde hair to the knees, serene closed-eye smile, golden halo like a crown of sunrays. White and gold layered robes with sky-blue trim, holds a floating golden tuning-fork sceptre. Regal, luminous, the 'poster girl' of the game.",
	},
	{
		"id": "cassiel", "name": "Cassiel", "title": "Aegis of Dawn",
		"faction": "celestial", "role": "guardian", "rarity": "epic",
		"bio": "Captain of the Gate Wardens. She has never taken a step backward, and she does not intend to start.",
		"look": "Armored paladin angel, short silver bob haircut, determined eyebrows. Polished white-gold plate armor with a sky-blue tabard, huge kite tower shield with a sunburst emblem held in front. Two medium feathered wings. Small simple halo.",
	},
	{
		"id": "liora", "name": "Liora", "title": "Hymn of Mending",
		"faction": "celestial", "role": "support", "rarity": "epic",
		"bio": "A temple novice whose lullabies close wounds. She is still learning which songs are safe to sing in battle.",
		"look": "Gentle healer angel with rose-gold twin tails tied with ribbons, big kind eyes, blushing cheeks. Cream and pale pink dress with gold embroidery, carries a small golden lyre. Two small fluffy wings, flower-shaped halo.",
	},
	{
		"id": "uriela", "name": "Uriela", "title": "the Sunlance",
		"faction": "celestial", "role": "striker", "rarity": "rare",
		"bio": "A spear maiden of the outer bastions, eager to prove the old stories about her namesake true.",
		"look": "Energetic spear maiden, high honey-blonde ponytail, confident grin. Azure and white light armor with gold trim, holds a long golden spear with a sun-shaped blade. Two swept-back wings, thin halo ring.",
	},
	{
		"id": "nuriel", "name": "Nuriel", "title": "Dawn Scout",
		"faction": "celestial", "role": "assassin", "rarity": "rare",
		"bio": "A quiet scout who hunts in the moment between night and morning. Says little, misses nothing.",
		"look": "Boyish youth (male), short messy pale-gold hair, half-mask covering mouth and nose in white cloth. Hooded sky-blue scout cloak over light leather, twin short daggers glowing with white light. Small sharp wings, faint thin halo.",
	},
	# ---------------- INFERNAL (crimson, ember orange, obsidian) ----------------
	{
		"id": "mordessa", "name": "Mordessa", "title": "the Ember Queen",
		"faction": "infernal", "role": "striker", "rarity": "legendary",
		"bio": "Queen of the Ninth Furnace. She lost the war, kept the crown, and has decided the war is not over.",
		"look": "Demon queen with large curled black ram horns, long wavy black hair with crimson ends, sharp golden eyes and a confident smirk. Black and crimson gothic armor-dress with gold filigree, small crown between the horns, huge greatsword wreathed in orange flame resting on her shoulder. Leathery bat wings, thin spaded tail.",
	},
	{
		"id": "brakka", "name": "Brakka", "title": "Brimstone Bulwark",
		"faction": "infernal", "role": "guardian", "rarity": "epic",
		"bio": "A furnace-golem's grandson with a heart softer than his hide. Loyal to Mordessa, and to anyone who feeds him.",
		"look": "Big stocky male demon (chibi but broad), dark red skin, thick short horns, friendly tusked grin. Heavy obsidian armor with glowing magma cracks, enormous molten gauntlets, chain belt. No wings; a thick tail.",
	},
	{
		"id": "vesper", "name": "Vesper", "title": "Mistress of Ember Rain",
		"faction": "infernal", "role": "caster", "rarity": "epic",
		"bio": "A succubus scholar who reads the future in falling ash. Her forecasts are always right, and always fire.",
		"look": "Elegant succubus mage, long straight wine-red hair with side bangs, half-lidded teasing eyes, small curved horns. Black and purple witch outfit with high collar and crimson ribbons, floating orb of hellfire in one hand. Small bat wings, heart-spaded tail.",
	},
	{
		"id": "imra", "name": "Imra", "title": "Lantern of Pacts",
		"faction": "infernal", "role": "support", "rarity": "rare",
		"bio": "An imp shaman who brokers small, fair deals. Mostly fair. Fair-ish.",
		"look": "Tiny mischievous imp girl, short spiky orange hair, small stubby horns, big toothy grin, pointed ears. Patchwork crimson shaman robe with bone beads, holds a staff with a hanging lantern containing a green-orange flame. Tiny bat wings, curly tail.",
	},
	{
		"id": "kessa", "name": "Kessa", "title": "Ashen Claw",
		"faction": "infernal", "role": "assassin", "rarity": "rare",
		"bio": "A hellcat bounty hunter. Twelve contracts, twelve trophies, and one very full scrapbook.",
		"look": "Cat-like demon girl with black cat ears AND small horns, short choppy black hair with red streak, slit-pupil amber eyes, fang smile. Sleek black bodysuit with red straps and a scarf, twin curved sickles. Long cat tail, no wings.",
	},
	# ---------------- FALLEN (violet, silver, teal ash) ----------------
	{
		"id": "noctaire", "name": "Noctaire", "title": "Eclipse Reaper",
		"faction": "fallen", "role": "assassin", "rarity": "legendary",
		"bio": "Once Heaven's executioner, she cut her own wings rather than carry out one final order. She still keeps the blade.",
		"look": "Fallen angel with long straight silver hair, cold violet eyes, one cracked dark halo tilted on her head. Tattered black feathered wings with violet tips. Black and violet gothic coat-dress with silver buckles, huge crescent scythe with a violet glow. Melancholic and beautiful.",
	},
	{
		"id": "orrin", "name": "Orrin", "title": "the Chained Oath",
		"faction": "fallen", "role": "guardian", "rarity": "epic",
		"bio": "A knight who swore to guard a gate that no longer exists. He guards his friends now, with the same chains.",
		"look": "Stoic male fallen knight, shaggy ash-grey hair, scar over one eye. Cracked silver armor wrapped with broken chains, violet cape. Holds a heavy chain-wrapped tower shield. Grey ragged wings, a broken halo hanging from a chain on his belt.",
	},
	{
		"id": "sable", "name": "Sable", "title": "Censer of Dusk",
		"faction": "fallen", "role": "support", "rarity": "epic",
		"bio": "A fallen nun who still holds services in ruined chapels. Her congregation is mostly ghosts. They come every week.",
		"look": "Calm fallen nun, long dark-teal hair under a black-and-violet veil, gentle sad smile. Dark nun habit with silver trim, swinging a silver censer trailing violet smoke. Grey feathered wings, faint dim halo.",
	},
	{
		"id": "lucen", "name": "Lucen", "title": "Twinfeather Duelist",
		"faction": "fallen", "role": "striker", "rarity": "rare",
		"bio": "One wing white, one wing black. He insists he has not chosen a side. His rapier disagrees, daily.",
		"look": "Flamboyant male duelist, wavy shoulder-length white hair with black tips, confident smile. Violet and silver duelist coat with frilled collar, slim rapier. Asymmetric wings: one white feathered, one black feathered. No halo.",
	},
	{
		"id": "ashra", "name": "Ashra", "title": "Witch of Ash",
		"faction": "fallen", "role": "caster", "rarity": "rare",
		"bio": "She burned her own heaven down by accident. Now she studies fire very, very carefully.",
		"look": "Young ash witch, messy grey hair with violet streaks, sleepy eyes, cracked violet halo. Oversized grey witch hat with silver star pins, layered violet robes with burned hem, holds a crooked wand with violet flame. Small grey wings.",
	},
]


static func all() -> Array[Dictionary]:
	return ROSTER


static func get_def(id: String) -> Dictionary:
	for h in ROSTER:
		if h.id == id:
			return h
	return {}


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for h in ROSTER:
		out.append(h.id)
	return out
