extends GutTest

const LocalGame = preload("res://scenes/game/local_game.gd")
const GameCard = preload("res://scenes/game/game_card.gd")
const Enums = preload("res://scenes/game/enums.gd")
var game_logic : LocalGame
var default_deck = CardDefinitions.get_deck_from_str_id("king")
const TestCardId1 = 50001
const TestCardId2 = 50002
const TestCardId3 = 50003
const TestCardId4 = 50004
const TestCardId5 = 50005

var player1 : LocalGame.Player
var player2 : LocalGame.Player

func default_game_setup():
	game_logic = LocalGame.new()
	var seed_value = randi()
	game_logic.initialize_game(default_deck, default_deck, "p1", "p2", Enums.PlayerId.PlayerId_Player, seed_value)
	game_logic.draw_starting_hands_and_begin()
	game_logic.do_mulligan(game_logic.player, [])
	game_logic.do_mulligan(game_logic.opponent, [])
	player1 = game_logic.player
	player2 = game_logic.opponent
	game_logic.get_latest_events()

func give_player_specific_card(player, def_id, card_id):
	var card_def = CardDefinitions.get_card(def_id)
	var card = GameCard.new(card_id, card_def, "image", player.my_id)
	var card_db = game_logic.get_card_database()
	card_db._test_insert_card(card)
	player.hand.append(card)

func give_specific_cards(p1, id1, p2, id2):
	if p1:
		give_player_specific_card(p1, id1, TestCardId1)
	if p2:
		give_player_specific_card(p2, id2, TestCardId2)

func position_players(p1, loc1, p2, loc2):
	p1.arena_location = loc1
	p2.arena_location = loc2

func give_gauge(player, amount):
	for i in range(amount):
		player.add_to_gauge(player.deck[0])
		player.deck.remove_at(0)

func validate_has_event(events, event_type, target_player, number = null):
	for event in events:
		if event['event_type'] == event_type:
			if event['event_player'] == target_player.my_id:
				if number != null and event['number'] == number:
					return
				elif number == null:
					return
	fail_test("Event not found: %s" % event_type)

func before_each():
	default_game_setup()

	gut.p("ran setup", 2)

func after_each():
	game_logic.teardown()
	game_logic.free()
	gut.p("ran teardown", 2)

func before_all():
	gut.p("ran run setup", 2)

func after_all():
	gut.p("ran run teardown", 2)

func do_and_validate_strike(player, card_id, ex_card_id = -1):
	assert_true(game_logic.can_do_strike(player))
	assert_true(game_logic.do_strike(player, card_id, false, ex_card_id))
	var events = game_logic.get_latest_events()
	validate_has_event(events, Enums.EventType.EventType_Strike_Started, player, card_id)
	if game_logic.game_state == Enums.GameState.GameState_Strike_Opponent_Response or game_logic.game_state == Enums.GameState.GameState_PlayerDecision:
		pass
	else:
		fail_test("Unexpected game state after strike")

func do_strike_response(player, card_id, ex_card = -1):
	assert_true(game_logic.do_strike(player, card_id, false, ex_card))
	var events = game_logic.get_latest_events()
	return events

func advance_turn(player):
	assert_true(game_logic.do_prepare(player))
	if player.hand.size() > 7:
		var cards = []
		var to_discard = player.hand.size() - 7
		for i in range(to_discard):
			cards.append(player.hand[i].id)
		assert_true(game_logic.do_discard_to_max(player, cards))

func validate_gauge(player, amount, id):
	assert_eq(len(player.gauge), amount)
	if len(player.gauge) != amount: return
	if amount == 0: return
	for card in player.gauge:
		if card.id == id:
			return
	fail_test("Didn't have required card in gauge.")

func validate_discard(player, amount, id):
	assert_eq(len(player.discards), amount)
	if len(player.discards) != amount: return
	if amount == 0: return
	for card in player.discards:
		if card.id == id:
			return
	fail_test("Didn't have required card in discard.")

func handle_simultaneous_effects(initiator, defender):
	while game_logic.game_state == Enums.GameState.GameState_PlayerDecision and game_logic.decision_info.type == Enums.DecisionType.DecisionType_ChooseSimultaneousEffect:
		var decider = initiator
		if game_logic.decision_info.player == defender.my_id:
			decider = defender
		assert_true(game_logic.do_choice(decider, 0), "Failed simuleffect choice")

func execute_strike(initiator, defender, init_card : String, def_card : String, init_choices, def_choices, init_ex = false, def_ex = false,
		init_seals = [], def_force_discard = [], init_extra_cost = 0, init_force_special = false):
	var all_events = []
	give_specific_cards(initiator, init_card, defender, def_card)
	if init_ex:
		give_player_specific_card(initiator, init_card, TestCardId3)
		do_and_validate_strike(initiator, TestCardId1, TestCardId3)
	else:
		do_and_validate_strike(initiator, TestCardId1)

	if game_logic.game_state == Enums.GameState.GameState_PlayerDecision and game_logic.active_strike.strike_state == game_logic.StrikeState.StrikeState_Initiator_SetEffects:
		# just changing this for specter
		game_logic.do_choose_to_discard(initiator, init_seals)

	if def_ex:
		give_player_specific_card(defender, def_card, TestCardId4)
		all_events += do_strike_response(defender, TestCardId2, TestCardId4)
	elif def_card:
		all_events += do_strike_response(defender, TestCardId2)

	if game_logic.game_state == Enums.GameState.GameState_PlayerDecision and game_logic.active_strike.strike_state == game_logic.StrikeState.StrikeState_Defender_SetEffects:
		game_logic.do_force_for_effect(defender, def_force_discard, false)

	# Pay any costs from gauge or hand
	if game_logic.active_strike and game_logic.active_strike.strike_state == game_logic.StrikeState.StrikeState_Initiator_PayCosts:
		if init_force_special:
			var cost = game_logic.active_strike.initiator_card.definition['force_cost'] + init_extra_cost
			var cards = []
			for i in range(cost):
				cards.append(initiator.hand[i].id)
			game_logic.do_pay_strike_cost(initiator, cards, false)
		else:
			var cost = game_logic.active_strike.initiator_card.definition['gauge_cost'] + init_extra_cost
			if 'gauge_cost_reduction' in game_logic.active_strike.initiator_card.definition and game_logic.active_strike.initiator_card.definition['gauge_cost_reduction'] == 'per_sealed_normal':
				cost -= initiator.get_sealed_count_of_type("normal")
			var cards = []
			for i in range(cost):
				cards.append(initiator.gauge[i].id)
			game_logic.do_pay_strike_cost(initiator, cards, false)

	# Pay any costs from gauge
	if game_logic.active_strike and game_logic.active_strike.strike_state == game_logic.StrikeState.StrikeState_Defender_PayCosts:
		var cost = game_logic.active_strike.defender_card.definition['gauge_cost']
		var cards = []
		for i in range(cost):
			cards.append(defender.gauge[i].id)
		game_logic.do_pay_strike_cost(defender, cards, false)

	handle_simultaneous_effects(initiator, defender)

	for i in range(init_choices.size()):
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
		assert_true(game_logic.do_choice(initiator, init_choices[i]))
		handle_simultaneous_effects(initiator, defender)
	handle_simultaneous_effects(initiator, defender)

	for i in range(def_choices.size()):
		assert_eq(game_logic.game_state, Enums.GameState.GameState_PlayerDecision)
		assert_true(game_logic.do_choice(defender, def_choices[i]))
		handle_simultaneous_effects(initiator, defender)

	var events = game_logic.get_latest_events()
	all_events += events
	return all_events

func validate_positions(p1, l1, p2, l2):
	assert_eq(p1.arena_location, l1)
	assert_eq(p2.arena_location, l2)

func validate_life(p1, l1, p2, l2):
	assert_eq(p1.life, l1)
	assert_eq(p2.life, l2)

##
## Tests start here
##

func test_king_draw_after_continuous_boost():
	position_players(player1, 3, player2, 7)
	player1.hand = []
	give_player_specific_card(player1, "standard_normal_grasp", TestCardId3)

	assert_true(game_logic.do_boost(player1, TestCardId3, []))
	assert_eq(len(player1.hand), 2)
	advance_turn(player2)

func test_king_no_draw_after_immediate_boost():
	position_players(player1, 3, player2, 7)
	player1.hand = []
	give_player_specific_card(player1, "standard_normal_cross", TestCardId3)

	assert_true(game_logic.do_boost(player1, TestCardId3, []))
	assert_true(game_logic.do_choice(player1, 0))
	validate_positions(player1, 4, player2, 7)
	assert_eq(len(player1.hand), 1)
	advance_turn(player2)

func test_king_decree_boost():
	position_players(player1, 3, player2, 7)
	var init_hand_size = len(player1.hand)
	var decree_id = -1
	for card in player1.set_aside_cards:
		if card.definition['id'] == "king_decree_kinglystrut":
			decree_id = card.id
			break

	assert_true(game_logic.do_boost(player1, decree_id, [player1.hand[0].id, player1.hand[1].id, player1.hand[2].id]))
	assert_true(game_logic.do_choice(player1, 1))
	validate_positions(player1, 5, player2, 7)
	assert_eq(len(player1.hand), init_hand_size - 1)
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_assault", "standard_normal_sweep", [], [], false, false)
	validate_positions(player1, 6, player2, 7)
	validate_life(player1, 26, player2, 24)
	assert_true(player1.is_card_in_sealed(decree_id))
	advance_turn(player1)

func test_king_healing_hammer_miss():
	position_players(player1, 4, player2, 7)

	execute_strike(player1, player2, "king_healinghammer", "standard_normal_grasp", [], [], false, false,
		[], [], 0, true)
	validate_positions(player1, 4, player2, 7)
	validate_life(player1, 30, player2, 30)
	advance_turn(player2)

func test_king_healing_hammer_no_seal():
	position_players(player1, 4, player2, 6)
	player1.life = 25

	execute_strike(player1, player2, "king_healinghammer", "standard_normal_grasp", [1], [], false, false,
		[], [], 0, true)
	validate_positions(player1, 4, player2, 6)
	validate_life(player1, 25, player2, 28)
	advance_turn(player2)

func test_king_healing_hammer_seal():
	position_players(player1, 4, player2, 6)
	player1.life = 25
	player1.hand = []
	give_player_specific_card(player1, "standard_normal_grasp", TestCardId3)
	give_player_specific_card(player1, "standard_normal_grasp", TestCardId4)
	player1.discard_hand()
	give_player_specific_card(player1, "standard_normal_cross", TestCardId5)

	execute_strike(player1, player2, "king_healinghammer", "standard_normal_grasp", [0], [], false, false,
		[], [], 0, true)
	validate_positions(player1, 4, player2, 6)
	validate_life(player1, 29, player2, 28)
	assert_true(player1.is_card_in_discards(TestCardId3))
	assert_true(player1.is_card_in_gauge(TestCardId4))
	assert_true(player1.is_card_in_gauge(TestCardId5))
	assert_true(player1.is_card_in_sealed(TestCardId1))
	advance_turn(player2)

func test_king_unsteady_ground_opponent_spends():
	position_players(player1, 3, player2, 7)
	give_player_specific_card(player1, "king_scepterslam", TestCardId3)
	give_gauge(player2, 1)

	assert_true(game_logic.do_boost(player1, TestCardId3, [player1.hand[0].id]))
	assert_true(game_logic.do_choice(player1, 3))
	validate_positions(player1, 3, player2, 5)
	assert_true(game_logic.do_gauge_for_effect(player2, [player2.gauge[0].id]))
	advance_turn(player2)

func test_king_unsteady_ground_opponent_doesnt_spend():
	position_players(player1, 3, player2, 7)
	give_player_specific_card(player1, "king_scepterslam", TestCardId3)
	give_gauge(player2, 1)

	assert_true(game_logic.do_boost(player1, TestCardId3, [player1.hand[0].id]))
	assert_true(game_logic.do_choice(player1, 3))
	validate_positions(player1, 3, player2, 5)
	assert_true(game_logic.do_gauge_for_effect(player2, []))
	assert_true(game_logic.do_prepare(player1))
	advance_turn(player2)

func test_king_unsteady_ground_opponent_cant_spend():
	position_players(player1, 3, player2, 7)
	give_player_specific_card(player1, "king_scepterslam", TestCardId3)

	assert_true(game_logic.do_boost(player1, TestCardId3, [player1.hand[0].id]))
	assert_true(game_logic.do_choice(player1, 3))
	validate_positions(player1, 3, player2, 5)
	assert_true(game_logic.do_prepare(player1))
	advance_turn(player2)

func test_king_spin_jump_draw_boost():
	position_players(player1, 2, player2, 4)
	player1.hand = []
	give_player_specific_card(player1, "king_shoulderbash", TestCardId3)
	give_player_specific_card(player1, "standard_normal_grasp", TestCardId4)

	execute_strike(player1, player2, "king_spinjump", "standard_normal_sweep", [1, 0], [], false, false,
		[], [], 0, true)
	assert_true(game_logic.do_boost(player1, TestCardId3, [TestCardId4]))

	validate_positions(player1, 8, player2, 4)
	validate_life(player1, 30, player2, 25)
	assert_eq(len(player1.hand), 4)
	assert_true(player1.is_card_in_continuous_boosts(TestCardId3))
	advance_turn(player2)

func test_king_edict_no_copies():
	position_players(player1, 3, player2, 6)
	give_player_specific_card(player1, "king_spinjump", TestCardId3)

	assert_true(game_logic.do_boost(player1, TestCardId3, [player1.hand[0].id]))
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_sweep", "standard_normal_spike", [], [], false, false)
	validate_positions(player1, 3, player2, 6)
	validate_life(player1, 25, player2, 30)
	advance_turn(player2)

func test_king_edict_with_copy():
	position_players(player1, 3, player2, 6)
	give_player_specific_card(player1, "king_spinjump", TestCardId3)
	give_player_specific_card(player1, "standard_normal_sweep", TestCardId4)
	player1.discard([TestCardId4])

	assert_true(game_logic.do_boost(player1, TestCardId3, [player1.hand[0].id]))
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_sweep", "standard_normal_spike", [], [], false, false)
	validate_positions(player1, 3, player2, 6)
	validate_life(player1, 30, player2, 23)
	advance_turn(player2)

func test_king_king_of_cards_no_force():
	position_players(player1, 4, player2, 6)
	give_gauge(player1, 3)
	player1.discard_hand()
	player1.draw(3)

	execute_strike(player1, player2, "king_kingofcards", "standard_normal_grasp", [], [], false, false)
	assert_true(game_logic.do_force_for_effect(player1, [], false))
	validate_positions(player1, 4, player2, 6)
	validate_life(player1, 30, player2, 24)
	assert_eq(len(player1.gauge), 1)
	advance_turn(player2)

func test_king_king_of_cards_multiple_of_three_force():
	position_players(player1, 4, player2, 6)
	give_gauge(player1, 3)
	player1.discard_hand()
	player1.draw(6)

	execute_strike(player1, player2, "king_kingofcards", "standard_normal_grasp", [], [], false, false)
	assert_true(game_logic.do_force_for_effect(player1, player1.hand.map(func(card): return card.id), true))
	validate_positions(player1, 4, player2, 6)
	validate_life(player1, 30, player2, 18)
	assert_eq(len(player1.gauge), 3)
	advance_turn(player2)

func test_king_king_of_cards_not_multiple_of_three_force():
	position_players(player1, 4, player2, 6)
	give_gauge(player1, 3)
	player1.discard_hand()
	player1.draw(4)

	execute_strike(player1, player2, "king_kingofcards", "standard_normal_grasp", [], [], false, false)
	assert_true(game_logic.do_force_for_effect(player1, player1.hand.map(func(card): return card.id), true))
	validate_positions(player1, 4, player2, 6)
	validate_life(player1, 30, player2, 21)
	assert_eq(len(player1.gauge), 2)
	advance_turn(player2)

func test_king_kingmaker_neither_exceeded():
	position_players(player1, 1, player2, 4)
	give_player_specific_card(player1, "king_kingofcards", TestCardId3)

	assert_true(game_logic.do_boost(player1, TestCardId3, []))
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_sweep", "standard_normal_dive", [], [], false, false)
	validate_positions(player1, 1, player2, 2)
	validate_life(player1, 25, player2, 24)
	advance_turn(player2)

func test_king_kingmaker_player_exceeded():
	position_players(player1, 1, player2, 4)
	give_player_specific_card(player1, "king_kingofcards", TestCardId3)
	player1.exceeded = true

	assert_true(game_logic.do_boost(player1, TestCardId3, []))
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_sweep", "standard_normal_dive", [], [], false, false)
	validate_positions(player1, 1, player2, 4)
	validate_life(player1, 30, player2, 24)
	advance_turn(player2)

func test_king_kingmaker_opponent_exceeded():
	position_players(player1, 1, player2, 4)
	give_player_specific_card(player1, "king_kingofcards", TestCardId3)
	player2.exceeded = true

	assert_true(game_logic.do_boost(player1, TestCardId3, []))
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_sweep", "standard_normal_dive", [], [], false, false)
	validate_positions(player1, 1, player2, 2)
	validate_life(player1, 25, player2, 22)
	advance_turn(player2)

func test_king_kingmaker_both_exceeded():
	position_players(player1, 1, player2, 4)
	give_player_specific_card(player1, "king_kingofcards", TestCardId3)
	player1.exceeded = true
	player2.exceeded = true

	assert_true(game_logic.do_boost(player1, TestCardId3, []))
	advance_turn(player2)

	execute_strike(player1, player2, "standard_normal_sweep", "standard_normal_dive", [], [], false, false)
	validate_positions(player1, 1, player2, 4)
	validate_life(player1, 30, player2, 22)
	advance_turn(player2)

func test_king_victory_trumpets_miss():
	position_players(player1, 3, player2, 5)
	give_gauge(player1, 2)

	execute_strike(player1, player2, "king_victorytrumpets", "standard_normal_grasp", [], [], false, false)
	validate_positions(player1, 3, player2, 5)
	validate_life(player1, 30, player2, 30)
	assert_eq(len(player1.gauge), 0)
	advance_turn(player2)

func test_king_victory_trumpets_sustain_decree():
	position_players(player1, 3, player2, 7)
	give_gauge(player1, 2)
	var decree_id = -1
	for card in player1.set_aside_cards:
		if card.definition['id'] == "king_decree_lordlymight":
			decree_id = card.id
			break

	assert_true(game_logic.do_boost(player1, decree_id, [player1.hand[0].id, player1.hand[1].id, player1.hand[2].id]))
	advance_turn(player2)

	execute_strike(player1, player2, "king_victorytrumpets", "standard_normal_grasp", [], [], false, false)
	validate_positions(player1, 3, player2, 4)
	validate_life(player1, 30, player2, 29)
	assert_eq(len(player1.gauge), 1)
	assert_true(player1.is_card_in_continuous_boosts(decree_id))
	advance_turn(player2)

func test_king_victory_trumpets_no_range_one_effect():
	position_players(player1, 4, player2, 3)
	player1.exceeded = true
	give_gauge(player1, 2)
	var decree_id = -1
	for card in player1.set_aside_cards:
		if card.definition['id'] == "king_decree_paytowin":
			decree_id = card.id
			break

	assert_true(game_logic.do_boost(player1, decree_id, [player1.hand[0].id, player1.hand[1].id, player1.hand[2].id, player1.hand[3].id]))
	advance_turn(player2)
	var other_hand_size = len(player2.hand)

	execute_strike(player1, player2, "king_victorytrumpets", "standard_normal_sweep", [], [], false, false)
	validate_positions(player1, 4, player2, 7)
	validate_life(player1, 29, player2, 27)
	assert_eq(len(player2.hand), other_hand_size)
	assert_true(player1.is_card_in_continuous_boosts(decree_id))
	advance_turn(player2)

func test_king_victory_trumpets_sneaky_range_one_effect():
	position_players(player1, 2, player2, 9)
	player1.exceeded = true
	give_gauge(player1, 2)
	var decree_id = -1
	for card in player1.set_aside_cards:
		if card.definition['id'] == "king_decree_paytowin":
			decree_id = card.id
			break

	assert_true(game_logic.do_boost(player1, decree_id, [player1.hand[0].id, player1.hand[1].id, player1.hand[2].id, player1.hand[3].id]))
	advance_turn(player2)
	var other_hand_size = len(player2.hand)

	execute_strike(player1, player2, "king_victorytrumpets", "standard_normal_sweep", [], [], false, false)
	validate_positions(player1, 2, player2, 6)
	validate_life(player1, 30, player2, 27)
	assert_eq(len(player2.hand), other_hand_size-2)
	assert_true(player1.is_card_in_continuous_boosts(decree_id))
	advance_turn(player2)


func test_king_royal_tribute():
	position_players(player1, 1, player2, 4)
	player1.hand = []
	give_player_specific_card(player1, "king_victorytrumpets", TestCardId3)
	give_player_specific_card(player1, "standard_normal_cross", TestCardId4)

	var init_hand_size = len(player1.hand)
	assert_true(game_logic.do_boost(player1, TestCardId3, []))
	assert_true(game_logic.do_choice(player1, 0))
	assert_eq(len(player1.hand), init_hand_size+1)
	assert_true(player1.is_card_in_discards(TestCardId3))

	assert_true(game_logic.do_boost(player1, TestCardId4, []))
	assert_true(game_logic.do_choice(player1, 2))
	validate_positions(player1, 5, player2, 4)
	advance_turn(player2)


func test_king_exceed_2_glorious():
	position_players(player1, 1, player2, 4)
	player1.exceeded = true
	player1.discard_hand()
	give_gauge(player1, 4)
	var decree_id = -1
	for card in player1.set_aside_cards:
		if card.definition['id'] == "king_decree_paytowin":
			decree_id = card.id
			break
	assert_true(game_logic.do_boost(player1, decree_id, player1.get_card_ids_in_gauge()))
	advance_turn(player2)
	execute_strike(player1, player2, "standard_normal_assault", "standard_normal_assault", [], [], false, false)
	validate_positions(player1, 3, player2, 4)
	validate_life(player1, 30, player2, 23)
	give_gauge(player1, 4)
	for card in player1.set_aside_cards:
		if card.definition['id'] == "king_decree_magnificentcape":
			decree_id = card.id
			break
	assert_true(game_logic.do_boost(player1, decree_id, player1.get_card_ids_in_gauge()))
	assert_true(game_logic.do_choice(player1, 1))
	validate_positions(player1, 3, player2, 4)

	advance_turn(player2)
	assert_eq(player1.continuous_boosts.size(), 1)
	assert_eq(player1.sealed.size(), 1)
	assert_eq(player1.set_aside_cards.size(), 2)
