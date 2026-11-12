# The Auction — Balance Scale

Open `auction_chamber.tscn` to inspect the assembled level blockout.

The scene instances the chamber, auction table, four chairs, four overhead acid-pot assemblies, and the round display. Four player spawn markers are provided around the table.

The acid pot assembly is in `AcidPot.tscn` and uses the controller in `assets/balance_scale/acid_pot.gd`.

This is the first visual assembly pass. Multiplayer bidding, player assignment, pot fill values, and round progression are not connected yet. Import and runtime validation still need to be performed in Godot 4.7.
