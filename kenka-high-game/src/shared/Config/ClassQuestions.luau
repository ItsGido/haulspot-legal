-- Class minigame questions (blueprint section 6.4, "Class minigame").
-- ClassService picks PerClass random questions each class period; PassCorrect or better passes.
-- Each question: { Q = text, Choices = { 4 strings }, Answer = index of the correct choice }.
-- The server shuffles the choices before sending them, so Answer only has to be right here.

local ClassQuestions = {
	PerClass = 5,
	PassCorrect = 3,
	SubmitGraceSeconds = 3, -- late submissions accepted this long after the class period ends

	Questions = {
		-- Math
		{ Q = "What is 7 × 8?", Choices = { "54", "56", "58", "64" }, Answer = 2 },
		{ Q = "What is 144 ÷ 12?", Choices = { "10", "11", "12", "14" }, Answer = 3 },
		{ Q = "What is 15% of 200?", Choices = { "15", "20", "30", "35" }, Answer = 3 },
		{ Q = "Solve: 3x + 4 = 19. What is x?", Choices = { "3", "5", "6", "7" }, Answer = 2 },
		{ Q = "What is the square root of 81?", Choices = { "7", "8", "9", "11" }, Answer = 3 },
		{ Q = "A ramen bowl costs ¥120. How much for 3 bowls?", Choices = { "¥300", "¥340", "¥360", "¥380" }, Answer = 3 },
		{ Q = "What is 2 to the power of 5?", Choices = { "10", "16", "25", "32" }, Answer = 4 },
		{ Q = "How many degrees are in a triangle's angles in total?", Choices = { "90", "180", "270", "360" }, Answer = 2 },
		{ Q = "What is 0.5 + 0.25?", Choices = { "0.55", "0.7", "0.75", "1.0" }, Answer = 3 },
		{ Q = "What is the next prime number after 7?", Choices = { "9", "10", "11", "13" }, Answer = 3 },
		{ Q = "What is 1,000 − 375?", Choices = { "525", "625", "635", "725" }, Answer = 2 },
		{ Q = "How many sides does a hexagon have?", Choices = { "5", "6", "7", "8" }, Answer = 2 },
		{ Q = "What is 9 × 9?", Choices = { "72", "79", "81", "99" }, Answer = 3 },
		{ Q = "What is the area of a 4 × 6 rectangle?", Choices = { "10", "20", "24", "26" }, Answer = 3 },

		-- Japanese words
		{ Q = "What does \"kenka\" (喧嘩) mean?", Choices = { "Friend", "Fight", "School", "Lunch" }, Answer = 2 },
		{ Q = "What does \"sensei\" mean?", Choices = { "Student", "Teacher", "Principal", "Janitor" }, Answer = 2 },
		{ Q = "\"Arigatou\" means…", Choices = { "Goodbye", "Sorry", "Thank you", "Hello" }, Answer = 3 },
		{ Q = "What is \"neko\" in English?", Choices = { "Dog", "Bird", "Fish", "Cat" }, Answer = 4 },
		{ Q = "What does \"sakura\" refer to?", Choices = { "Cherry blossom", "Maple leaf", "Bamboo", "Pine tree" }, Answer = 1 },
		{ Q = "\"Senpai\" is…", Choices = { "A younger student", "An older student or senior", "A teacher", "A rival school" }, Answer = 2 },
		{ Q = "What does \"ichi, ni, san\" count?", Choices = { "1, 2, 3", "3, 2, 1", "10, 20, 30", "A, B, C" }, Answer = 1 },
		{ Q = "\"Ohayou gozaimasu\" is said…", Choices = { "At night", "In the morning", "At lunch", "When leaving" }, Answer = 2 },
		{ Q = "What does \"gakkou\" mean?", Choices = { "Train", "Hospital", "School", "Store" }, Answer = 3 },
		{ Q = "\"Mizu\" means…", Choices = { "Fire", "Water", "Wind", "Earth" }, Answer = 2 },
		{ Q = "What does \"banchō\" mean in delinquent slang?", Choices = { "The class clown", "The top delinquent / boss", "The hall monitor", "A new student" }, Answer = 2 },
		{ Q = "\"Itadakimasu\" is said…", Choices = { "Before eating", "After a fight", "When waking up", "At a funeral" }, Answer = 1 },
		{ Q = "\"Konbini\" is short for…", Choices = { "Convenience store", "Concert hall", "Computer", "Combination" }, Answer = 1 },

		-- Japanese culture
		{ Q = "What is the capital of Japan?", Choices = { "Osaka", "Kyoto", "Tokyo", "Sapporo" }, Answer = 3 },
		{ Q = "What is the traditional black boys' school uniform called?", Choices = { "Kimono", "Gakuran", "Yukata", "Hakama" }, Answer = 2 },
		{ Q = "Which mountain is the tallest in Japan?", Choices = { "Mt. Aso", "Mt. Fuji", "Mt. Tate", "Mt. Kita" }, Answer = 2 },
		{ Q = "What is a \"sento\"?", Choices = { "A public bathhouse", "A train station", "A shrine gate", "A rice field" }, Answer = 1 },
		{ Q = "What do you usually take off before entering a Japanese home?", Choices = { "Hat", "Jacket", "Shoes", "Watch" }, Answer = 3 },
		{ Q = "What is Japan's currency?", Choices = { "Won", "Yuan", "Yen", "Baht" }, Answer = 3 },
		{ Q = "Which sport features wrestlers in a ring called a dohyō?", Choices = { "Judo", "Sumo", "Kendo", "Karate" }, Answer = 2 },
		{ Q = "Onigiri are mostly made of…", Choices = { "Noodles", "Rice", "Bread", "Tofu" }, Answer = 2 },
		{ Q = "What is the Japanese bullet train called?", Choices = { "Shinkansen", "Maglev-go", "Tokkyu Rail", "Hikari Bus" }, Answer = 1 },
		{ Q = "The red gate at a Shinto shrine is called a…", Choices = { "Torii", "Pagoda", "Shoji", "Tatami" }, Answer = 1 },
		{ Q = "Hanami is the custom of…", Choices = { "Viewing cherry blossoms", "Watching fireworks", "Making mochi", "Visiting graves" }, Answer = 1 },
		{ Q = "What are tatami?", Choices = { "Paper lanterns", "Straw floor mats", "Wooden sandals", "Folding fans" }, Answer = 2 },

		-- School trivia
		{ Q = "In Japan, the school year usually starts in…", Choices = { "January", "April", "September", "June" }, Answer = 2 },
		{ Q = "Who usually cleans the classrooms in Japanese schools?", Choices = { "Janitors", "Teachers", "The students", "Parents" }, Answer = 3 },
		{ Q = "Which planet is known as the Red Planet?", Choices = { "Venus", "Jupiter", "Mars", "Saturn" }, Answer = 3 },
		{ Q = "What gas do plants absorb from the air?", Choices = { "Oxygen", "Carbon dioxide", "Helium", "Nitrogen" }, Answer = 2 },
		{ Q = "How many continents are there?", Choices = { "5", "6", "7", "8" }, Answer = 3 },
		{ Q = "Water boils at what temperature at sea level?", Choices = { "50 °C", "90 °C", "100 °C", "120 °C" }, Answer = 3 },
		{ Q = "Which is the largest ocean?", Choices = { "Atlantic", "Indian", "Arctic", "Pacific" }, Answer = 4 },
		{ Q = "What is H2O?", Choices = { "Salt", "Water", "Hydrogen gas", "Oxygen" }, Answer = 2 },
		{ Q = "Shoes worn inside a Japanese school are called…", Choices = { "Uwabaki", "Geta", "Zori", "Tabi" }, Answer = 1 },
		{ Q = "How many minutes are in 2 hours?", Choices = { "100", "120", "140", "200" }, Answer = 2 },
	},
}

return ClassQuestions
