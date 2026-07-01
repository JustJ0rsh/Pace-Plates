# Built-In Workout Template Library - Implementation Plan

## Overview
Add a comprehensive library of pre-built workout templates organized by experience level and fitness goals. When users tap the + button, they choose between starting from a template or starting a blank workout.

---

## Experience Levels & Goals Structure

### Experience Level 1: BEGINNER (Never worked out or returning after 6+ months)
**Goals:**
1. **Full Body Foundation** - Build overall strength and learn proper form
2. **Weight Loss Starter** - High-rep circuits for calorie burn
3. **Mobility & Recovery** - Flexibility and injury prevention
4. **Home Workout Basics** - No equipment needed
5. **Gym Orientation** - Learn the machines safely
6. **Core Strength** - Build foundational core stability
7. **Bodyweight Mastery** - Master basic movements

### Experience Level 2: INTERMEDIATE (6+ months consistent training)
**Goals:**
1. **Muscle Building** - Hypertrophy-focused split routines
2. **Strength Gains** - Progressive overload for major lifts
3. **Athletic Performance** - Power and explosiveness
4. **Fat Loss & Toning** - Metabolic conditioning
5. **Upper Body Focus** - Chest, back, shoulders, arms
6. **Lower Body Power** - Legs and glutes development
7. **Push/Pull/Legs Split** - Classic 3-day rotation
8. **Functional Fitness** - Real-world movement patterns

### Experience Level 3: ADVANCED (2+ years consistent training)
**Goals:**
1. **Powerlifting** - Max strength in big 3 lifts
2. **Bodybuilding** - Aesthetic muscle development
3. **Olympic Lifting** - Cleans, snatches, jerks
4. **Endurance Strength** - High-volume training
5. **Hybrid Athlete** - Strength + conditioning combo
6. **Specialization** - Target weak points
7. **Peak Performance** - Competition prep
8. **Volume Training** - High-frequency splits

---

## Template Library Structure

### Data Model Addition to `WorkoutTemplate.swift`

```swift
// Add new properties to WorkoutTemplate
var experienceLevel: String? = nil // "beginner", "intermediate", "advanced"
var goal: String? = nil // "full_body_foundation", "weight_loss", etc.
var isBuiltIn: Bool = false // true for pre-loaded templates, false for user/AI created
var difficulty: Int? = nil // 1-5 scale
var estimatedDuration: Int? = nil // minutes
var equipment: [String]? = nil // ["barbell", "dumbbells", "bench", etc.]
var muscleGroups: [String]? = nil // ["chest", "back", "legs", etc.]
var tags: [String]? = nil // ["beginner-friendly", "home-workout", etc.]
```

---

## Complete Template Definitions

### BEGINNER LEVEL

#### Goal 1: Full Body Foundation (5 Templates)

**Template 1: Total Body Basics A**
- Estimated Duration: 45 min
- Equipment: Dumbbells, Bench
- Exercises:
  1. Goblet Squat - 3x10
  2. Dumbbell Bench Press - 3x10
  3. Bent Over Row - 3x10
  4. Overhead Press - 3x8
  5. Romanian Deadlift - 3x10
  6. Plank - 3x30sec

**Template 2: Total Body Basics B**
- Estimated Duration: 45 min
- Equipment: Dumbbells, Bench
- Exercises:
  1. Dumbbell Lunge - 3x10 each leg
  2. Incline Dumbbell Press - 3x10
  3. Single Arm Row - 3x10 each arm
  4. Lateral Raise - 3x12
  5. Leg Curl - 3x12
  6. Dead Bug - 3x12

**Template 3: Full Body Circuit**
- Estimated Duration: 40 min
- Equipment: Dumbbells, Bodyweight
- Exercises:
  1. Air Squat - 3x15
  2. Push-ups - 3x10
  3. Bodyweight Row - 3x10
  4. Dumbbell Clean - 3x8
  5. Step-ups - 3x12 each leg
  6. Bird Dog - 3x10 each side

**Template 4: Beginner Compound Movements**
- Estimated Duration: 50 min
- Equipment: Barbell, Dumbbells
- Exercises:
  1. Trap Bar Deadlift - 3x8 (or KB/DB deadlift)
  2. Dumbbell Chest Press - 3x10
  3. Cable Row - 3x12
  4. Leg Press - 3x12
  5. Dumbbell Shoulder Press - 3x10
  6. Farmer's Carry - 3x30 yards

**Template 5: Foundation Strength**
- Estimated Duration: 45 min
- Equipment: Mixed
- Exercises:
  1. Box Squat - 3x10
  2. Cable Chest Fly - 3x12
  3. Lat Pulldown - 3x10
  4. Dumbbell Arnold Press - 3x10
  5. Glute Bridge - 3x15
  6. Pallof Press - 3x12 each side

#### Goal 2: Weight Loss Starter (5 Templates)

**Template 1: Fat Burn Circuit A**
- Estimated Duration: 35 min
- Equipment: Dumbbells, Bodyweight
- Exercises:
  1. Jumping Jacks - 3x30sec
  2. Dumbbell Squat to Press - 3x15
  3. Mountain Climbers - 3x20
  4. Dumbbell Renegade Row - 3x10 each
  5. Burpees - 3x10
  6. Bicycle Crunches - 3x20

**Template 2: Metabolic Conditioning**
- Estimated Duration: 30 min
- Equipment: Kettlebell, Bodyweight
- Exercises:
  1. KB Swing - 4x20
  2. Push-up to T - 3x10 each side
  3. Goblet Squat - 4x15
  4. Plank Jacks - 3x20
  5. KB Clean - 3x10 each arm
  6. High Knees - 3x30sec

**Template 3: Cardio Strength Combo**
- Estimated Duration: 40 min
- Equipment: Dumbbells, Jump Rope
- Exercises:
  1. Jump Rope - 3x1min
  2. Dumbbell Thruster - 3x12
  3. Box Step-ups - 3x15 each
  4. Battle Ropes - 3x30sec
  5. Dumbbell Swing - 3x20
  6. Plank to Push-up - 3x10

**Template 4: HIIT Strength**
- Estimated Duration: 35 min
- Equipment: Bodyweight, Dumbbells
- Exercises:
  1. Squat Jumps - 4x12
  2. Push-ups - 4x15
  3. Lunge Jumps - 4x10 each
  4. Dumbbell Row - 4x12
  5. Tuck Jumps - 3x10
  6. Russian Twist - 3x30

**Template 5: Beginner EMOM** (Every Minute On the Minute)
- Estimated Duration: 30 min
- Equipment: Light dumbbells
- Exercises:
  1. Air Squats - 15 reps
  2. Push-ups - 10 reps
  3. KB Swings - 15 reps
  4. Sit-ups - 15 reps
  5. Burpees - 8 reps
  Notes: Rotate through exercises, 1 per minute for 30 min

#### Goal 3: Mobility & Recovery (5 Templates)

**Template 1: Active Recovery Flow**
- Estimated Duration: 30 min
- Equipment: Yoga mat
- Exercises:
  1. Cat-Cow Stretch - 3x10
  2. World's Greatest Stretch - 2x5 each
  3. Hip Circles - 2x10 each direction
  4. Scapular Wall Slides - 3x12
  5. Glute Bridge Hold - 3x30sec
  6. Child's Pose - 2x60sec

**Template 2: Flexibility Foundation**
- Estimated Duration: 25 min
- Equipment: Yoga mat, Band
- Exercises:
  1. Band Pull-Aparts - 3x20
  2. Leg Swings - 2x15 each leg
  3. Thoracic Rotation - 3x10 each
  4. Pigeon Pose - 2x45sec each
  5. Standing Pike Stretch - 3x30sec
  6. Shoulder Dislocations - 3x15

**Template 3: Core Stability**
- Estimated Duration: 30 min
- Equipment: Mat
- Exercises:
  1. Dead Bug - 3x12
  2. Bird Dog - 3x10 each
  3. Side Plank - 3x30sec each
  4. Hollow Body Hold - 3x20sec
  5. Glute Bridge - 3x15
  6. Bear Crawl - 3x20 yards

**Template 4: Lower Body Mobility**
- Estimated Duration: 25 min
- Equipment: Foam roller
- Exercises:
  1. 90/90 Hip Stretch - 2x60sec each
  2. Cossack Squat - 3x8 each
  3. Ankle Circles - 2x15 each
  4. Foam Roll IT Band - 2x60sec each
  5. Seated Hip Opener - 2x45sec each
  6. Calf Stretch - 3x30sec each

**Template 5: Upper Body Mobility**
- Estimated Duration: 25 min
- Equipment: Band, Foam roller
- Exercises:
  1. Band Shoulder Pass-Through - 3x15
  2. Foam Roll Upper Back - 2x60sec
  3. Wall Angels - 3x12
  4. Doorway Pec Stretch - 2x45sec each
  5. Neck Circles - 2x10 each direction
  6. Wrist Mobility Drill - 3x15

#### Goal 4: Home Workout Basics (5 Templates)

**Template 1: No Equipment Full Body**
- Estimated Duration: 30 min
- Equipment: None
- Exercises:
  1. Bodyweight Squat - 4x15
  2. Push-ups - 4x12
  3. Reverse Lunge - 3x12 each
  4. Pike Push-up - 3x10
  5. Glute Bridge - 4x15
  6. Plank - 3x45sec

**Template 2: Living Room Circuit**
- Estimated Duration: 35 min
- Equipment: Chair, Towel
- Exercises:
  1. Chair Dips - 3x12
  2. Bulgarian Split Squat - 3x10 each (rear foot on chair)
  3. Towel Rows - 3x15 (doorway anchor)
  4. Wall Sits - 3x45sec
  5. Diamond Push-ups - 3x10
  6. Superman Hold - 3x30sec

**Template 3: Bodyweight Strength Builder**
- Estimated Duration: 40 min
- Equipment: None
- Exercises:
  1. Single Leg Deadlift - 3x10 each
  2. Decline Push-ups - 3x12 (feet elevated)
  3. Pistol Squat Progression - 3x8 each
  4. Handstand Hold - 3x15sec (against wall)
  5. Nordic Curl - 3x6 (assisted)
  6. L-Sit Progression - 3x20sec

**Template 4: Apartment-Friendly Workout**
- Estimated Duration: 30 min
- Equipment: Resistance band (optional)
- Exercises:
  1. Static Squat - 3x12
  2. Wide Push-ups - 3x12
  3. Glute Kickback - 3x15 each
  4. Band Pull-Apart - 3x20
  5. Side Plank Raise - 3x10 each
  6. V-Ups - 3x12

**Template 5: Total Body Bodyweight**
- Estimated Duration: 35 min
- Equipment: None
- Exercises:
  1. Jump Squats - 3x12
  2. Burpees - 3x10
  3. Walking Lunge - 3x20 steps
  4. Spiderman Push-ups - 3x10
  5. Single Leg Hip Thrust - 3x12 each
  6. Hollow Body Rock - 3x20

#### Goal 5: Gym Orientation (5 Templates)

**Template 1: Machine Basics A**
- Estimated Duration: 40 min
- Equipment: Machines
- Exercises:
  1. Leg Press - 3x12
  2. Chest Press Machine - 3x12
  3. Lat Pulldown - 3x12
  4. Shoulder Press Machine - 3x10
  5. Leg Curl - 3x12
  6. Cable Crunch - 3x15

**Template 2: Machine Basics B**
- Estimated Duration: 40 min
- Equipment: Machines
- Exercises:
  1. Hack Squat - 3x12
  2. Pec Deck - 3x12
  3. Seated Row - 3x12
  4. Lateral Raise Machine - 3x12
  5. Leg Extension - 3x12
  6. Ab Machine - 3x15

**Template 3: Cable Station Intro**
- Estimated Duration: 35 min
- Equipment: Cable machine
- Exercises:
  1. Cable Squat - 3x12
  2. Cable Chest Fly - 3x12
  3. Cable Row - 3x12
  4. Cable Lateral Raise - 3x15
  5. Cable Woodchop - 3x12 each
  6. Cable Crunch - 3x15

**Template 4: Free Weight Introduction**
- Estimated Duration: 45 min
- Equipment: Dumbbells, Barbell
- Exercises:
  1. Goblet Squat - 3x10
  2. Dumbbell Bench Press - 3x10
  3. Dumbbell Row - 3x10 each
  4. Barbell Curl - 3x10
  5. Dumbbell Overhead Press - 3x10
  6. Dumbbell Deadlift - 3x10

**Template 5: Mixed Equipment Flow**
- Estimated Duration: 45 min
- Equipment: Mixed
- Exercises:
  1. Smith Machine Squat - 3x12
  2. Cable Chest Press - 3x12
  3. Machine Row - 3x12
  4. Dumbbell Shoulder Press - 3x10
  5. Leg Press - 3x12
  6. Assisted Pull-up - 3x8

#### Goal 6: Core Strength (5 Templates)

**Template 1: Core Foundation**
- Estimated Duration: 25 min
- Equipment: Mat
- Exercises:
  1. Plank - 3x45sec
  2. Side Plank - 3x30sec each
  3. Dead Bug - 3x12
  4. Bird Dog - 3x10 each
  5. Glute Bridge - 3x15
  6. Pallof Press - 3x12 each

**Template 2: Anti-Rotation Core**
- Estimated Duration: 30 min
- Equipment: Cable, Band
- Exercises:
  1. Pallof Press - 3x15 each
  2. Single Arm Farmer's Carry - 3x40 yards each
  3. Copenhagen Plank - 3x20sec each
  4. Cable Chop - 3x12 each
  5. Band Anti-Rotation - 3x15 each
  6. Suitcase Deadlift - 3x10 each

**Template 3: Core Power**
- Estimated Duration: 30 min
- Equipment: Medicine ball
- Exercises:
  1. Med Ball Slam - 4x12
  2. Med Ball Russian Twist - 3x30
  3. Med Ball Overhead Throw - 3x10
  4. Med Ball Side Toss - 3x12 each
  5. Med Ball V-Up - 3x12
  6. Med Ball Plank Pull - 3x10

**Template 4: Abs & Obliques**
- Estimated Duration: 25 min
- Equipment: Mat, Weight plate
- Exercises:
  1. Weighted Crunch - 3x15
  2. Russian Twist - 3x30
  3. Side Crunch - 3x15 each
  4. Leg Raise - 3x12
  5. Bicycle Crunch - 3x20
  6. Plank to Pike - 3x10

**Template 5: Functional Core**
- Estimated Duration: 30 min
- Equipment: Kettlebell
- Exercises:
  1. Turkish Get-Up - 3x3 each
  2. Windmill - 3x8 each
  3. KB Swing - 4x15
  4. Suitcase Carry - 3x50 yards each
  5. KB Around the World - 3x10 each direction
  6. Hollow Body Hold - 3x30sec

#### Goal 7: Bodyweight Mastery (5 Templates)

**Template 1: Push Progression**
- Estimated Duration: 35 min
- Equipment: None
- Exercises:
  1. Regular Push-ups - 4x12
  2. Wide Push-ups - 3x10
  3. Diamond Push-ups - 3x8
  4. Archer Push-ups - 3x6 each
  5. Decline Push-ups - 3x10
  6. Push-up Hold - 3x20sec

**Template 2: Pull Progression**
- Estimated Duration: 35 min
- Equipment: Pull-up bar
- Exercises:
  1. Dead Hang - 3x30sec
  2. Scapular Pull-ups - 3x10
  3. Negative Pull-ups - 3x5
  4. Band-Assisted Pull-ups - 3x8
  5. Inverted Row - 3x12
  6. Australian Pull-ups - 3x15

**Template 3: Leg Mastery**
- Estimated Duration: 40 min
- Equipment: None
- Exercises:
  1. Pistol Squat (assisted) - 3x8 each
  2. Bulgarian Split Squat - 3x12 each
  3. Single Leg RDL - 3x10 each
  4. Shrimp Squat - 3x8 each
  5. Nordic Curl (assisted) - 3x6
  6. Calf Raise - 3x20

**Template 4: Core & Balance**
- Estimated Duration: 30 min
- Equipment: None
- Exercises:
  1. L-Sit Progression - 3x20sec
  2. Dragon Flag Progression - 3x6
  3. Human Flag Hold - 3x10sec each
  4. Front Lever Tuck - 3x15sec
  5. Planche Lean - 3x20sec
  6. Handstand Practice - 3x30sec

**Template 5: Full Body Calisthenics**
- Estimated Duration: 45 min
- Equipment: Pull-up bar
- Exercises:
  1. Pull-ups - 5x5
  2. Dips - 4x8
  3. Pistol Squats - 3x8 each
  4. Muscle-up Progression - 3x5
  5. Front Lever Raises - 3x8
  6. Handstand Push-up Progression - 3x5

---

### INTERMEDIATE LEVEL

#### Goal 1: Muscle Building (6 Templates)

**Template 1: Chest & Triceps Hypertrophy**
- Estimated Duration: 60 min
- Equipment: Barbell, Dumbbells, Cables
- Exercises:
  1. Barbell Bench Press - 4x8
  2. Incline Dumbbell Press - 4x10
  3. Cable Chest Fly - 3x12
  4. Dips - 3x10
  5. Overhead Tricep Extension - 3x12
  6. Cable Tricep Pushdown - 3x15

**Template 2: Back & Biceps Hypertrophy**
- Estimated Duration: 60 min
- Equipment: Barbell, Dumbbells, Cables
- Exercises:
  1. Barbell Row - 4x8
  2. Pull-ups - 4x8
  3. Dumbbell Row - 4x10 each
  4. Cable Lat Pulldown - 3x12
  5. Barbell Curl - 3x10
  6. Hammer Curl - 3x12

**Template 3: Leg Hypertrophy A**
- Estimated Duration: 60 min
- Equipment: Barbell, Leg machines
- Exercises:
  1. Back Squat - 4x10
  2. Romanian Deadlift - 4x10
  3. Leg Press - 3x12
  4. Walking Lunges - 3x12 each
  5. Leg Curl - 3x15
  6. Calf Raise - 4x20

**Template 4: Shoulder Hypertrophy**
- Estimated Duration: 55 min
- Equipment: Dumbbells, Cables, Barbell
- Exercises:
  1. Overhead Press - 4x8
  2. Dumbbell Lateral Raise - 4x12
  3. Face Pulls - 4x15
  4. Arnold Press - 3x10
  5. Cable Upright Row - 3x12
  6. Rear Delt Fly - 3x15

**Template 5: Push Day**
- Estimated Duration: 65 min
- Equipment: Mixed
- Exercises:
  1. Bench Press - 5x5
  2. Overhead Press - 4x8
  3. Incline DB Press - 4x10
  4. Lateral Raise - 4x12
  5. Dips - 3x12
  6. Tricep Rope Extension - 3x15

**Template 6: Pull Day**
- Estimated Duration: 65 min
- Equipment: Mixed
- Exercises:
  1. Deadlift - 4x6
  2. Pull-ups - 4x8
  3. Barbell Row - 4x8
  4. Dumbbell Row - 3x10 each
  5. Face Pulls - 4x15
  6. Barbell Curl - 3x10
  7. Hammer Curl - 3x12

#### Goal 2: Strength Gains (6 Templates)

**Template 1: Squat Focus**
- Estimated Duration: 70 min
- Equipment: Barbell, Rack
- Exercises:
  1. Back Squat - 5x5 (heavy)
  2. Front Squat - 3x8
  3. Pause Squat - 3x5
  4. Bulgarian Split Squat - 3x8 each
  5. Leg Curl - 3x10
  6. Ab Wheel - 3x12

**Template 2: Bench Focus**
- Estimated Duration: 65 min
- Equipment: Barbell, Dumbbells
- Exercises:
  1. Barbell Bench Press - 5x5 (heavy)
  2. Close Grip Bench - 3x8
  3. Incline Bench - 4x6
  4. Dumbbell Press - 3x8
  5. Weighted Dips - 3x8
  6. Cable Fly - 3x12

**Template 3: Deadlift Focus**
- Estimated Duration: 65 min
- Equipment: Barbell
- Exercises:
  1. Conventional Deadlift - 5x3 (heavy)
  2. Romanian Deadlift - 4x8
  3. Deficit Deadlift - 3x6
  4. Barbell Row - 4x8
  5. Good Morning - 3x10
  6. Hanging Leg Raise - 3x12

**Template 4: Overhead Press Focus**
- Estimated Duration: 60 min
- Equipment: Barbell, Dumbbells
- Exercises:
  1. Standing Overhead Press - 5x5 (heavy)
  2. Push Press - 3x6
  3. Seated DB Press - 4x8
  4. Lateral Raise - 4x12
  5. Face Pulls - 4x15
  6. Shrugs - 3x12

**Template 5: Big 3 Day**
- Estimated Duration: 75 min
- Equipment: Barbell
- Exercises:
  1. Squat - 5x3
  2. Bench Press - 5x3
  3. Deadlift - 5x3
  4. Overhead Press - 3x8
  5. Barbell Row - 3x8
  6. Plank - 3x60sec

**Template 6: Accessory Strength**
- Estimated Duration: 55 min
- Equipment: Mixed
- Exercises:
  1. Weighted Pull-ups - 4x6
  2. Weighted Dips - 4x6
  3. Pendlay Row - 4x8
  4. Front Squat - 4x6
  5. Floor Press - 3x8
  6. Farmer's Walk - 4x50 yards

#### Goal 3: Athletic Performance (6 Templates)

**Template 1: Power Development**
- Estimated Duration: 55 min
- Equipment: Barbell, Platform
- Exercises:
  1. Power Clean - 5x3
  2. Box Jump - 4x5
  3. Med Ball Slam - 4x10
  4. Broad Jump - 4x5
  5. Trap Bar Jump Squat - 3x6
  6. Medicine Ball Chest Pass - 3x10

**Template 2: Speed & Explosiveness**
- Estimated Duration: 50 min
- Equipment: Light weights, Box
- Exercises:
  1. Jump Squat - 5x5
  2. Clapping Push-up - 4x8
  3. Box Jump - 4x8
  4. Medicine Ball Overhead Throw - 4x8
  5. Broad Jump - 4x5
  6. Sprint (short distance) - 6x20 yards

**Template 3: Agility & Coordination**
- Estimated Duration: 45 min
- Equipment: Cones, Ladder
- Exercises:
  1. Ladder Drills - 4x20 yards
  2. Cone Drills - 4 rounds
  3. Single Leg Hop - 3x10 each
  4. Lateral Bounds - 3x12
  5. Depth Jump - 4x5
  6. Rotational Med Ball Throw - 3x10 each

**Template 4: Plyometric Power**
- Estimated Duration: 50 min
- Equipment: Box, Med ball
- Exercises:
  1. Depth Jump to Box Jump - 4x5
  2. Plyo Push-ups - 4x8
  3. Tuck Jumps - 4x10
  4. Lateral Box Jump - 3x8 each
  5. Single Leg Bounds - 3x8 each
  6. Burpee Box Jump - 3x10

**Template 5: Functional Athlete**
- Estimated Duration: 60 min
- Equipment: Mixed
- Exercises:
  1. Clean and Press - 4x6
  2. Front Squat - 4x8
  3. Pull-ups - 4x10
  4. Sled Push - 4x40 yards
  5. Battle Ropes - 4x30sec
  6. Turkish Get-Up - 3x3 each

**Template 6: Sport Performance**
- Estimated Duration: 55 min
- Equipment: Mixed
- Exercises:
  1. Hang Clean - 5x3
  2. Box Jump - 4x6
  3. Weighted Step-up - 3x8 each
  4. Medicine Ball Rotational Throw - 3x10 each
  5. Single Leg RDL - 3x10 each
  6. Pallof Press - 3x12 each

#### Goal 4: Fat Loss & Toning (6 Templates)

**Template 1: Metabolic Strength Circuit**
- Estimated Duration: 45 min
- Equipment: Dumbbells, KB
- Exercises:
  1. KB Swing - 4x20
  2. Dumbbell Thruster - 4x15
  3. Renegade Row - 3x10 each
  4. Jump Squat - 4x15
  5. Push-up to T - 3x10 each
  6. Mountain Climbers - 4x30

**Template 2: HIIT Resistance**
- Estimated Duration: 40 min
- Equipment: Dumbbells
- Exercises:
  1. Dumbbell Snatch - 4x10 each
  2. Burpee - 4x12
  3. DB Walking Lunge - 3x20 steps
  4. Plank Jack - 4x20
  5. DB Swing - 4x20
  6. Bike Crunch - 3x30

**Template 3: Conditioning Circuit**
- Estimated Duration: 35 min
- Equipment: Mixed
- Exercises:
  1. Battle Ropes - 5x30sec
  2. Box Jump - 4x12
  3. Rowing Machine - 4x250m
  4. KB Clean - 3x10 each
  5. Sled Push - 4x30 yards
  6. Farmer's Walk - 4x50 yards

**Template 4: Toning Full Body**
- Estimated Duration: 50 min
- Equipment: Light-moderate weights
- Exercises:
  1. Goblet Squat - 4x15
  2. DB Bench Press - 4x12
  3. Cable Row - 4x15
  4. Lateral Raise - 3x15
  5. Romanian Deadlift - 3x12
  6. Cable Crunch - 3x20

**Template 5: Sculpt & Burn**
- Estimated Duration: 45 min
- Equipment: Dumbbells
- Exercises:
  1. DB Lunge to Press - 3x12 each
  2. Renegade Row - 3x12 each
  3. DB Squat to Curl - 3x15
  4. Walkout to Push-up - 3x10
  5. DB Swing - 3x20
  6. Plank to Down Dog - 3x12

**Template 6: Cardio Strength Fusion**
- Estimated Duration: 50 min
- Equipment: Mixed
- Exercises:
  1. Assault Bike - 5x30sec sprint
  2. DB Thruster - 4x12
  3. Ski Erg - 4x200m
  4. KB Swing - 4x20
  5. Rowing - 4x250m
  6. Burpee Box Jump - 3x10

#### Goal 5: Upper Body Focus (6 Templates)

**Template 1: Chest Blast**
- Estimated Duration: 55 min
- Equipment: Barbell, Dumbbells, Cables
- Exercises:
  1. Flat Bench Press - 4x8
  2. Incline DB Press - 4x10
  3. Decline Bench - 3x10
  4. Cable Fly - 3x12
  5. Dumbbell Pullover - 3x12
  6. Push-up Drop Set - 3xFailure

**Template 2: Back Thickness**
- Estimated Duration: 60 min
- Equipment: Barbell, Dumbbells, Cables
- Exercises:
  1. Deadlift - 4x6
  2. Barbell Row - 4x8
  3. Wide Grip Pull-up - 4x8
  4. T-Bar Row - 3x10
  5. Dumbbell Row - 3x10 each
  6. Straight Arm Pulldown - 3x12

**Template 3: Shoulder Development**
- Estimated Duration: 55 min
- Equipment: Barbell, Dumbbells, Cables
- Exercises:
  1. Overhead Press - 4x8
  2. Arnold Press - 3x10
  3. Lateral Raise - 4x12
  4. Rear Delt Fly - 4x12
  5. Face Pull - 4x15
  6. Upright Row - 3x12

**Template 4: Arm Pump**
- Estimated Duration: 50 min
- Equipment: Barbell, Dumbbells, Cables
- Exercises:
  1. Barbell Curl - 4x10
  2. Close Grip Bench - 4x10
  3. Hammer Curl - 3x12
  4. Overhead Tricep Extension - 3x12
  5. Cable Curl - 3x15
  6. Cable Tricep Pushdown - 3x15
  7. 21s (Curls) - 2 sets

**Template 5: Push Specialization**
- Estimated Duration: 60 min
- Equipment: Mixed
- Exercises:
  1. Bench Press - 5x5
  2. Overhead Press - 4x6
  3. Incline DB Press - 4x10
  4. Dips - 4x10
  5. Lateral Raise - 4x12
  6. Close Grip Push-up - 3x15

**Template 6: Pull Specialization**
- Estimated Duration: 60 min
- Equipment: Mixed
- Exercises:
  1. Weighted Pull-up - 5x5
  2. Barbell Row - 4x8
  3. Dumbbell Row - 4x10 each
  4. Cable Row - 3x12
  5. Barbell Curl - 4x10
  6. Face Pull - 4x15

#### Goal 6: Lower Body Power (6 Templates)

**Template 1: Quad Dominant**
- Estimated Duration: 60 min
- Equipment: Barbell, Machines
- Exercises:
  1. Back Squat - 5x5
  2. Front Squat - 4x8
  3. Leg Press - 4x12
  4. Leg Extension - 3x15
  5. Walking Lunge - 3x20 steps
  6. Calf Raise - 4x20

**Template 2: Posterior Chain**
- Estimated Duration: 60 min
- Equipment: Barbell
- Exercises:
  1. Deadlift - 5x5
  2. Romanian Deadlift - 4x10
  3. Good Morning - 3x10
  4. Leg Curl - 4x12
  5. Glute Ham Raise - 3x8
  6. Back Extension - 3x15

**Template 3: Glute Builder**
- Estimated Duration: 55 min
- Equipment: Barbell, Bands, Machines
- Exercises:
  1. Hip Thrust - 4x10
  2. Romanian Deadlift - 4x10
  3. Bulgarian Split Squat - 3x10 each
  4. Cable Pull-Through - 3x12
  5. Banded Lateral Walk - 3x20 each direction
  6. Single Leg Glute Bridge - 3x12 each

**Template 4: Explosive Legs**
- Estimated Duration: 55 min
- Equipment: Barbell, Box
- Exercises:
  1. Jump Squat - 5x5
  2. Box Jump - 4x8
  3. Power Clean - 4x5
  4. Broad Jump - 4x5
  5. Single Leg Hop - 3x8 each
  6. Depth Jump - 4x5

**Template 5: Leg Hypertrophy**
- Estimated Duration: 65 min
- Equipment: Mixed
- Exercises:
  1. Back Squat - 4x10
  2. Leg Press - 4x12
  3. Romanian Deadlift - 4x10
  4. Walking Lunge - 3x12 each
  5. Leg Curl - 3x15
  6. Leg Extension - 3x15
  7. Calf Raise - 4x20

**Template 6: Unilateral Strength**
- Estimated Duration: 55 min
- Equipment: Dumbbells, Barbell
- Exercises:
  1. Bulgarian Split Squat - 4x10 each
  2. Single Leg RDL - 4x10 each
  3. Step-up - 3x12 each
  4. Single Leg Leg Press - 3x12 each
  5. Single Leg Hip Thrust - 3x12 each
  6. Single Leg Calf Raise - 3x15 each

#### Goal 7: Push/Pull/Legs Split (6 Templates)

**Template 1: Push A**
- Estimated Duration: 60 min
- Equipment: Barbell, Dumbbells
- Exercises:
  1. Flat Bench Press - 4x8
  2. Overhead Press - 4x8
  3. Incline DB Press - 3x10
  4. Lateral Raise - 3x12
  5. Dips - 3x10
  6. Cable Tricep Pushdown - 3x12

**Template 2: Pull A**
- Estimated Duration: 60 min
- Equipment: Barbell, Dumbbells
- Exercises:
  1. Deadlift - 4x6
  2. Pull-ups - 4x8
  3. Barbell Row - 4x8
  4. Face Pull - 3x15
  5. Barbell Curl - 3x10
  6. Hammer Curl - 3x12

**Template 3: Legs A**
- Estimated Duration: 60 min
- Equipment: Barbell, Machines
- Exercises:
  1. Back Squat - 4x8
  2. Romanian Deadlift - 4x10
  3. Leg Press - 3x12
  4. Leg Curl - 3x12
  5. Walking Lunge - 3x12 each
  6. Calf Raise - 4x20

**Template 4: Push B**
- Estimated Duration: 60 min
- Equipment: Dumbbells, Cables
- Exercises:
  1. Incline Barbell Press - 4x8
  2. DB Shoulder Press - 4x10
  3. Cable Chest Fly - 3x12
  4. Arnold Press - 3x10
  5. Overhead Tricep Extension - 3x12
  6. Cable Lateral Raise - 3x15

**Template 5: Pull B**
- Estimated Duration: 60 min
- Equipment: Mixed
- Exercises:
  1. Barbell Row - 4x8
  2. Weighted Pull-up - 4x6
  3. Dumbbell Row - 3x10 each
  4. Cable Lat Pulldown - 3x12
  5. Cable Curl - 3x12
  6. Preacher Curl - 3x12

**Template 6: Legs B**
- Estimated Duration: 60 min
- Equipment: Mixed
- Exercises:
  1. Front Squat - 4x8
  2. Leg Press - 4x12
  3. Bulgarian Split Squat - 3x10 each
  4. Leg Extension - 3x15
  5. Leg Curl - 3x15
  6. Seated Calf Raise - 4x20

#### Goal 8: Functional Fitness (6 Templates)

**Template 1: CrossFit-Style WOD A**
- Estimated Duration: 45 min
- Equipment: Barbell, Box, Pull-up bar
- Exercises:
  1. Thruster - 5 rounds of 21-15-9
  2. Pull-ups - (same rep scheme)
  3. Box Jump - 3x15
  4. Burpees - 3x15
  5. Rowing - 500m for time

**Template 2: Movement Mastery**
- Estimated Duration: 50 min
- Equipment: KB, Barbell
- Exercises:
  1. Turkish Get-Up - 3x3 each
  2. Clean and Jerk - 4x5
  3. Farmer's Walk - 4x50 yards
  4. Sled Push - 4x40 yards
  5. Rower - 4x250m
  6. Burpees - 3x15

**Template 3: Real World Strength**
- Estimated Duration: 55 min
- Equipment: Mixed
- Exercises:
  1. Tire Flip - 4x8
  2. Sled Drag - 4x40 yards
  3. Sandbag Carry - 4x50 yards
  4. Battle Ropes - 4x30sec
  5. Medicine Ball Slam - 4x15
  6. Farmer's Walk - 4x100 yards

**Template 4: Work Capacity**
- Estimated Duration: 40 min
- Equipment: Light weights
- Exercises:
  EMOM 20 minutes:
  - Min 1: KB Swing x15
  - Min 2: Burpees x10
  - Min 3: Box Jump x10
  - Min 4: Push-ups x15
  - Min 5: Rest
  (Repeat 4x)

**Template 5: GPP (General Physical Preparedness)**
- Estimated Duration: 50 min
- Equipment: Mixed
- Exercises:
  1. Power Clean - 4x5
  2. Front Squat - 4x8
  3. Pull-ups - 4x8
  4. Push Press - 4x8
  5. Row - 4x250m
  6. Plank - 3x60sec

**Template 6: Hybrid Athlete**
- Estimated Duration: 60 min
- Equipment: Mixed
- Exercises:
  1. Clean and Press - 5x5
  2. Box Jump - 4x10
  3. Assault Bike - 4x30sec sprint
  4. Dumbbell Snatch - 3x8 each
  5. Sled Push - 4x30 yards
  6. Burpee Pull-up - 3x10

---

### ADVANCED LEVEL

#### Goal 1: Powerlifting (7 Templates)

**Template 1: Heavy Squat Day**
- Estimated Duration: 90 min
- Equipment: Barbell, Rack
- Exercises:
  1. Back Squat - 6x3 @ 85-90%
  2. Pause Squat - 4x5
  3. Front Squat - 3x6
  4. Bulgarian Split Squat - 3x8 each
  5. Leg Curl - 3x10
  6. Ab Wheel - 4x12

**Template 2: Heavy Bench Day**
- Estimated Duration: 80 min
- Equipment: Barbell, Bench
- Exercises:
  1. Bench Press - 6x3 @ 85-90%
  2. Close Grip Bench - 4x5
  3. Incline Bench - 4x6
  4. Weighted Dips - 3x8
  5. DB Bench - 3x10
  6. Cable Fly - 3x15

**Template 3: Heavy Deadlift Day**
- Estimated Duration: 85 min
- Equipment: Barbell, Platform
- Exercises:
  1. Deadlift - 6x2 @ 85-92%
  2. Deficit Deadlift - 4x5
  3. Romanian Deadlift - 4x8
  4. Barbell Row - 4x8
  5. Good Morning - 3x10
  6. Hanging Leg Raise - 4x12

**Template 4: Volume Squat**
- Estimated Duration: 75 min
- Equipment: Barbell
- Exercises:
  1. Back Squat - 5x8 @ 70%
  2. Front Squat - 4x8
  3. Hack Squat - 4x10
  4. Leg Press - 4x12
  5. Walking Lunge - 3x20 steps
  6. Calf Raise - 5x15

**Template 5: Volume Bench**
- Estimated Duration: 70 min
- Equipment: Barbell, Dumbbells
- Exercises:
  1. Bench Press - 5x8 @ 70%
  2. Incline Bench - 4x8
  3. DB Bench - 4x10
  4. Overhead Press - 4x8
  5. Dips - 4x10
  6. Close Grip Bench - 3x10

**Template 6: Volume Deadlift**
- Estimated Duration: 75 min
- Equipment: Barbell
- Exercises:
  1. Deadlift - 5x5 @ 75%
  2. Romanian Deadlift - 4x8
  3. Deficit Deadlift - 3x6
  4. Barbell Row - 4x8
  5. Pull-ups - 4x8
  6. Good Morning - 3x10

**Template 7: Max Effort Day**
- Estimated Duration: 90 min
- Equipment: Full powerlifting setup
- Exercises:
  1. Work up to daily max on main lift (Squat/Bench/DL)
  2. Down sets - 3x3 @ 85%
  3. Primary accessory - 4x6
  4. Secondary accessory - 3x8
  5. Tertiary accessory - 3x10
  6. Core work - 4x15

#### Goal 2: Bodybuilding (8 Templates)

**Template 1: Chest & Calves**
- Estimated Duration: 75 min
- Equipment: Full gym
- Exercises:
  1. Bench Press - 4x8-10
  2. Incline DB Press - 4x10-12
  3. Cable Fly - 4x12-15
  4. Dips - 3x12
  5. Pec Deck - 3x15
  6. Standing Calf Raise - 5x15
  7. Seated Calf Raise - 4x20

**Template 2: Back & Hamstrings**
- Estimated Duration: 80 min
- Equipment: Full gym
- Exercises:
  1. Deadlift - 4x8
  2. Pull-ups - 4x10
  3. Barbell Row - 4x10
  4. Cable Row - 4x12
  5. Lat Pulldown - 3x15
  6. Leg Curl - 4x12
  7. Stiff Leg Deadlift - 3x12

**Template 3: Shoulders & Abs**
- Estimated Duration: 70 min
- Equipment: Full gym
- Exercises:
  1. Overhead Press - 4x8
  2. Arnold Press - 4x10
  3. Lateral Raise - 4x12-15
  4. Rear Delt Fly - 4x15
  5. Face Pull - 4x15
  6. Cable Crunch - 4x20
  7. Hanging Leg Raise - 4x15

**Template 4: Legs (Quad Focus)**
- Estimated Duration: 80 min
- Equipment: Full gym
- Exercises:
  1. Back Squat - 4x10
  2. Front Squat - 4x10
  3. Leg Press - 4x15
  4. Leg Extension - 4x15
  5. Walking Lunge - 3x15 each
  6. Hack Squat - 3x12

**Template 5: Arms**
- Estimated Duration: 60 min
- Equipment: Barbell, Dumbbells, Cables
- Exercises:
  1. Barbell Curl - 4x10
  2. Close Grip Bench - 4x10
  3. Preacher Curl - 3x12
  4. Overhead Tricep Extension - 3x12
  5. Hammer Curl - 3x15
  6. Cable Tricep Pushdown - 3x15
  7. Cable Curl - 3x15
  8. Rope Extension - 3x15

**Template 6: Push**
- Estimated Duration: 75 min
- Equipment: Full gym
- Exercises:
  1. Flat Bench - 4x8
  2. Overhead Press - 4x8
  3. Incline DB Press - 4x10
  4. DB Shoulder Press - 3x10
  5. Cable Fly - 3x12
  6. Lateral Raise - 4x15
  7. Dips - 3x12
  8. Overhead Tricep Extension - 3x12

**Template 7: Pull**
- Estimated Duration: 75 min
- Equipment: Full gym
- Exercises:
  1. Weighted Pull-up - 4x8
  2. Barbell Row - 4x8
  3. DB Row - 4x10 each
  4. Cable Row - 3x12
  5. Lat Pulldown - 3x12
  6. Face Pull - 4x15
  7. Barbell Curl - 3x10
  8. Hammer Curl - 3x12

**Template 8: Legs (Glute & Ham Focus)**
- Estimated Duration: 75 min
- Equipment: Full gym
- Exercises:
  1. Hip Thrust - 4x10
  2. Romanian Deadlift - 4x10
  3. Bulgarian Split Squat - 4x10 each
  4. Leg Curl - 4x12
  5. Cable Pull-Through - 3x15
  6. Glute Ham Raise - 3x10
  7. Single Leg RDL - 3x10 each

#### Goal 3: Olympic Lifting (6 Templates)

**Template 1: Snatch Focus**
- Estimated Duration: 85 min
- Equipment: Barbell, Platform, Bumpers
- Exercises:
  1. Power Snatch - 6x2 @ 75-80%
  2. Snatch Pull - 4x3 @ 90-100%
  3. Overhead Squat - 4x5
  4. Snatch Grip RDL - 3x8
  5. Pull-ups - 3x8
  6. Core Circuit - 3 rounds

**Template 2: Clean & Jerk Focus**
- Estimated Duration: 90 min
- Equipment: Barbell, Platform, Bumpers
- Exercises:
  1. Clean and Jerk - 6x2 @ 75-80%
  2. Clean Pull - 4x3 @ 90-100%
  3. Front Squat - 4x5
  4. Push Press - 4x5
  5. Barbell Row - 3x8
  6. Core work - 3 rounds

**Template 3: Strength Development**
- Estimated Duration: 75 min
- Equipment: Barbell
- Exercises:
  1. Back Squat - 5x5 @ 80%
  2. Snatch Grip Deadlift - 4x5
  3. Overhead Press - 4x6
  4. Front Rack Hold - 3x30sec
  5. Weighted Pull-up - 3x6
  6. Ab Wheel - 4x12

**Template 4: Technique & Speed**
- Estimated Duration: 70 min
- Equipment: Barbell, Light weights
- Exercises:
  1. Snatch - 8x2 @ 60-70% (speed)
  2. Clean - 6x2 @ 65-75% (speed)
  3. Hang Snatch - 4x3
  4. Hang Clean - 4x3
  5. Jerk - 5x3
  6. Mobility work - 15 min

**Template 5: Power Development**
- Estimated Duration: 80 min
- Equipment: Full setup
- Exercises:
  1. Power Clean - 6x3
  2. Power Snatch - 5x3
  3. Clean Pull - 4x5
  4. Box Jump - 4x5
  5. Med Ball Slam - 4x10
  6. Broad Jump - 4x5

**Template 6: Complex Training**
- Estimated Duration: 75 min
- Equipment: Barbell
- Exercises:
  1. Snatch + OHS - 5x(1+2)
  2. Clean + Front Squat + Jerk - 5x(1+2+1)
  3. Snatch Pull + Snatch - 4x(2+1)
  4. Clean Pull + Clean - 4x(2+1)
  5. Core & mobility - 20 min

#### Goal 4: Endurance Strength (6 Templates)

**Template 1: High Volume Upper**
- Estimated Duration: 75 min
- Equipment: Mixed
- Exercises:
  1. Bench Press - 5x12
  2. Barbell Row - 5x12
  3. Overhead Press - 4x15
  4. Pull-ups - 4x12
  5. Dips - 4x15
  6. Cable Fly - 3x20
  7. Face Pull - 3x20

**Template 2: High Volume Lower**
- Estimated Duration: 80 min
- Equipment: Mixed
- Exercises:
  1. Back Squat - 5x15
  2. Romanian Deadlift - 5x12
  3. Leg Press - 4x20
  4. Leg Curl - 4x15
  5. Leg Extension - 4x15
  6. Walking Lunge - 3x20 each
  7. Calf Raise - 5x25

**Template 3: Density Training**
- Estimated Duration: 60 min
- Equipment: Barbell, Dumbbells
- Exercises:
  - 10 rounds for time:
    1. Thruster x10
    2. Pull-up x10
    3. Box Jump x10
    4. Push-up x20
    5. KB Swing x20

**Template 4: Escalating Density**
- Estimated Duration: 50 min
- Equipment: Mixed
- Exercises:
  - 15-minute blocks (AMRAP):
    Block 1: DB Press x8, Row x8
    Block 2: Front Squat x8, RDL x8
    Block 3: Pull-up x6, Dip x8
  - Rest 3 min between blocks

**Template 5: High Rep Challenge**
- Estimated Duration: 70 min
- Equipment: Light weights
- Exercises:
  1. Goblet Squat - 100 reps (break as needed)
  2. Push-ups - 100 reps
  3. KB Swing - 100 reps
  4. Sit-ups - 100 reps
  5. Burpees - 50 reps
  6. Pull-ups - 50 reps

**Template 6: Lactate Threshold**
- Estimated Duration: 55 min
- Equipment: Barbell, moderate weight
- Exercises:
  - 5 rounds:
    1. Front Squat x15
    2. Bench Press x15
    3. Barbell Row x15
    4. Overhead Press x12
    5. Deadlift x10
  - Rest 3 min between rounds

#### Goal 5: Hybrid Athlete (7 Templates)

**Template 1: Strength + Conditioning**
- Estimated Duration: 75 min
- Equipment: Full gym
- Part A - Strength:
  1. Squat - 5x5
  2. Bench - 4x6
  Part B - Conditioning:
  3. Row 500m
  4. Assault Bike 1 min
  5. Burpees x20
  6. Rest 2 min, repeat 4 rounds

**Template 2: Power + Endurance**
- Estimated Duration: 70 min
- Equipment: Barbell, Cardio
- Part A:
  1. Power Clean - 5x3
  2. Box Jump - 5x5
  Part B:
  3. 5 rounds: Row 250m, 15 KB Swings, 10 Burpees

**Template 3: Olympic + MetCon**
- Estimated Duration: 75 min
- Equipment: Full setup
- Part A:
  1. Clean and Jerk - 6x2
  2. Snatch - 5x2
  Part B:
  3. AMRAP 15 min: 5 Thrusters, 10 Pull-ups, 15 Box Jumps

**Template 4: Strongman + Cardio**
- Estimated Duration: 80 min
- Equipment: Specialty items
- Exercises:
  1. Tire Flip - 5x8
  2. Farmer's Walk - 5x100 yards
  3. Sled Push - 5x50 yards
  4. Battle Ropes - 5x1 min
  5. Assault Bike - 5x2 min
  6. Burpees - 5x20

**Template 5: Gymnastic Strength + Endurance**
- Estimated Duration: 65 min
- Equipment: Rings, Pull-up bar
- Part A - Skill:
  1. Muscle-up practice - 10 min
  2. Handstand push-up - 5x5
  3. Pistol Squat - 4x8 each
  Part B - Endurance:
  4. 20 min AMRAP: 10 Pull-ups, 20 Push-ups, 30 Squats

**Template 6: Mixed Modal**
- Estimated Duration: 70 min
- Equipment: Everything
- Exercises:
  1. Deadlift - 5x5 @ 80%
  2. Row - 4x500m
  3. Weighted Pull-up - 4x6
  4. Assault Bike - 4x1 min sprint
  5. KB Swing - 4x20
  6. Ski Erg - 4x250m

**Template 7: Competition Prep**
- Estimated Duration: 90 min
- Equipment: Full setup
- Exercises:
  1. Squat - 5x3 @ 85%
  2. Bench - 5x3 @ 85%
  3. 1000m Row for time
  4. AMRAP 10 min: 5 Clean & Jerk, 10 Box Jump, 15 Wall Ball
  5. Farmer's Walk - 3x100 yards max weight
  6. 100 Burpees for time

#### Goal 6: Specialization (6 Templates)

**Template 1: Weak Point - Chest**
- Estimated Duration: 80 min
- Equipment: Full gym
- Exercises:
  1. Bench Press - 6x6
  2. Incline Bench - 5x8
  3. Decline Bench - 4x10
  4. DB Bench - 4x10
  5. Cable Fly - 4x12
  6. Dips - 4x12
  7. Pec Deck - 3x15

**Template 2: Weak Point - Back**
- Estimated Duration: 85 min
- Equipment: Full gym
- Exercises:
  1. Deadlift - 5x5
  2. Barbell Row - 5x8
  3. Weighted Pull-up - 5x6
  4. T-Bar Row - 4x10
  5. Cable Row - 4x12
  6. Lat Pulldown - 4x12
  7. Face Pull - 4x15

**Template 3: Weak Point - Legs**
- Estimated Duration: 90 min
- Equipment: Full gym
- Exercises:
  1. Back Squat - 6x6
  2. Front Squat - 4x8
  3. Romanian Deadlift - 4x10
  4. Leg Press - 4x15
  5. Leg Curl - 4x12
  6. Leg Extension - 4x15
  7. Walking Lunge - 3x20 each
  8. Calf Raise - 5x20

**Template 4: Weak Point - Shoulders**
- Estimated Duration: 70 min
- Equipment: Full gym
- Exercises:
  1. Overhead Press - 6x6
  2. Push Press - 4x6
  3. Arnold Press - 4x10
  4. Lateral Raise - 5x12
  5. Rear Delt Fly - 5x15
  6. Face Pull - 4x15
  7. Upright Row - 3x12

**Template 5: Weak Point - Arms**
- Estimated Duration: 65 min
- Equipment: Full gym
- Exercises:
  1. Close Grip Bench - 4x8
  2. Barbell Curl - 4x8
  3. Overhead Tricep Extension - 4x10
  4. Preacher Curl - 4x10
  5. Cable Pushdown - 4x12
  6. Cable Curl - 4x12
  7. Hammer Curl - 3x15
  8. Rope Extension - 3x15

**Template 6: Weak Point - Core**
- Estimated Duration: 45 min
- Equipment: Mixed
- Exercises:
  1. Weighted Crunch - 5x15
  2. Hanging Leg Raise - 4x12
  3. Ab Wheel - 4x15
  4. Cable Crunch - 4x20
  5. Russian Twist - 4x30
  6. Pallof Press - 4x15 each
  7. Plank - 4x90sec
  8. Side Plank - 3x60sec each

#### Goal 7: Peak Performance (6 Templates)

**Template 1: Competition Week - Day 1**
- Estimated Duration: 60 min
- Equipment: Full setup
- Exercises:
  1. Main Lift to opener (90%)
  2. Speed work - 6x3 @ 60%
  3. Light accessory - 3x8
  4. Mobility - 15 min

**Template 2: Competition Week - Day 2**
- Estimated Duration: 45 min
- Equipment: Light weights
- Exercises:
  1. Technique work
  2. Active recovery
  3. Stretching
  4. Visualization practice

**Template 3: Peak Strength**
- Estimated Duration: 75 min
- Equipment: Full powerlifting
- Exercises:
  1. Main lift - Work to 95%+ single
  2. Back-off sets - 3x2 @ 85%
  3. Primary accessory - 3x5
  4. Secondary accessory - 3x8
  5. Core - 3x12

**Template 4: Speed & Power Peak**
- Estimated Duration: 60 min
- Equipment: Barbell, light weights
- Exercises:
  1. Dynamic effort lifts - 10x2 @ 50-60%
  2. Plyometrics - 5x5
  3. Speed accessory - 3x6
  4. Power accessory - 3x8
  5. Conditioning - 10 min

**Template 5: Taper Week**
- Estimated Duration: 40 min
- Equipment: Barbell
- Exercises:
  1. Main lift - Singles to 80%
  2. Light accessory - 2x8
  3. Mobility work - 20 min

**Template 6: Test Day Simulation**
- Estimated Duration: 90 min
- Equipment: Competition setup
- Exercises:
  1. Warm-up protocol
  2. Attempt 1 - Opener
  3. Attempt 2 - Goal weight
  4. Attempt 3 - PR attempt
  5. Cool down

#### Goal 8: Volume Training (6 Templates)

**Template 1: German Volume Training - Chest/Back**
- Estimated Duration: 75 min
- Equipment: Barbell, Dumbbells
- Exercises:
  1. Bench Press - 10x10
  2. Barbell Row - 10x10
  3. Incline DB Press - 3x12
  4. Cable Row - 3x12
  5. Dips - 3x15
  6. Pull-ups - 3x12

**Template 2: GVT - Legs**
- Estimated Duration: 80 min
- Equipment: Barbell, Machines
- Exercises:
  1. Back Squat - 10x10
  2. Romanian Deadlift - 10x10
  3. Leg Press - 3x15
  4. Leg Curl - 3x15
  5. Calf Raise - 4x20

**Template 3: FST-7 - Arms**
- Estimated Duration: 60 min
- Equipment: Cables, Dumbbells
- Exercises:
  1. Barbell Curl - 3x10
  2. Close Grip Bench - 3x10
  3. Cable Curl - 7x12 (30sec rest)
  4. Cable Pushdown - 7x12 (30sec rest)
  5. Hammer Curl - 3x15
  6. Rope Extension - 3x15

**Template 4: High Frequency Upper**
- Estimated Duration: 70 min
- Equipment: Full gym
- Exercises:
  1. Bench Press - 8x5
  2. Overhead Press - 6x6
  3. Barbell Row - 6x8
  4. Pull-ups - 5x8
  5. Dips - 4x10
  6. Face Pull - 4x15

**Template 5: High Frequency Lower**
- Estimated Duration: 75 min
- Equipment: Barbell, Machines
- Exercises:
  1. Squat - 8x5
  2. Deadlift - 5x5
  3. Front Squat - 5x8
  4. Romanian Deadlift - 5x8
  5. Leg Press - 4x12
  6. Leg Curl - 4x12

**Template 6: Total Volume Overload**
- Estimated Duration: 90 min
- Equipment: Full gym
- Exercises:
  1. Squat - 5x10
  2. Bench - 5x10
  3. Deadlift - 4x8
  4. Overhead Press - 4x10
  5. Barbell Row - 5x10
  6. Pull-ups - 4x10
  7. Dips - 4x12
  8. Core circuit - 3 rounds

---

## UI/UX Implementation

### Updated + Button Flow

**When user taps + in Workouts tab:**

```
┌─────────────────────────────────┐
│  Start New Workout              │
├─────────────────────────────────┤
│                                 │
│  ┌───────────────────────────┐ │
│  │  📋 From Template         │ │
│  │  Browse workout library   │ │
│  └───────────────────────────┘ │
│                                 │
│  ┌───────────────────────────┐ │
│  │  ✏️  Blank Workout        │ │
│  │  Start from scratch       │ │
│  └───────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

### Template Browser UI

**Level 1: Experience Selection**
```
┌─────────────────────────────────┐
│  Choose Your Experience Level   │
├─────────────────────────────────┤
│                                 │
│  🌱 BEGINNER                    │
│  New to fitness or returning    │
│  7 goals • 35+ templates        │
│                                 │
│  💪 INTERMEDIATE                │
│  6+ months training             │
│  8 goals • 48+ templates        │
│                                 │
│  🔥 ADVANCED                    │
│  2+ years experience            │
│  8 goals • 50+ templates        │
│                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│                                 │
│  📚 My Custom Templates         │
│  AI-generated & saved           │
│                                 │
└─────────────────────────────────┘
```

**Level 2: Goal Selection**
```
┌─────────────────────────────────┐
│  ← Beginner  │  Choose Goal     │
├─────────────────────────────────┤
│                                 │
│  🏋️ Full Body Foundation       │
│  5 templates                    │
│                                 │
│  🔥 Weight Loss Starter         │
│  5 templates                    │
│                                 │
│  🧘 Mobility & Recovery         │
│  5 templates                    │
│                                 │
│  🏠 Home Workout Basics         │
│  5 templates                    │
│                                 │
│  🎯 Gym Orientation             │
│  5 templates                    │
│                                 │
│  💪 Core Strength               │
│  5 templates                    │
│                                 │
│  🦸 Bodyweight Mastery          │
│  5 templates                    │
│                                 │
└─────────────────────────────────┘
```

**Level 3: Template Selection**
```
┌─────────────────────────────────┐
│  ← Goals  │  Full Body Found... │
├─────────────────────────────────┤
│                                 │
│  ┌───────────────────────────┐ │
│  │ Total Body Basics A       │ │
│  │ 6 exercises • 45 min      │ │
│  │ 🏋️ Dumbbells, Bench       │ │
│  │ ⭐⭐ Difficulty            │ │
│  └───────────────────────────┘ │
│                                 │
│  ┌───────────────────────────┐ │
│  │ Total Body Basics B       │ │
│  │ 6 exercises • 45 min      │ │
│  │ 🏋️ Dumbbells, Bench       │ │
│  │ ⭐⭐ Difficulty            │ │
│  └───────────────────────────┘ │
│                                 │
│  ┌───────────────────────────┐ │
│  │ Full Body Circuit         │ │
│  │ 6 exercises • 40 min      │ │
│  │ 🏋️ Dumbbells, Bodyweight  │ │
│  │ ⭐⭐ Difficulty            │ │
│  └───────────────────────────┘ │
│                                 │
└─────────────────────────────────┘
```

**Level 4: Template Detail**
```
┌─────────────────────────────────┐
│  ← Templates │ Total Body Basi..│
├─────────────────────────────────┤
│                                 │
│  Total Body Basics A            │
│  ⭐⭐ Difficulty • 45 min        │
│                                 │
│  Equipment needed:              │
│  🏋️ Dumbbells • Bench           │
│                                 │
│  Target: Chest, Back, Legs,     │
│  Shoulders, Core                │
│                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│                                 │
│  Exercises (6)                  │
│                                 │
│  1️⃣ Goblet Squat                │
│     3 sets × 10 reps            │
│                                 │
│  2️⃣ Dumbbell Bench Press        │
│     3 sets × 10 reps            │
│                                 │
│  3️⃣ Bent Over Row               │
│     3 sets × 10 reps            │
│                                 │
│  4️⃣ Overhead Press              │
│     3 sets × 8 reps             │
│                                 │
│  5️⃣ Romanian Deadlift           │
│     3 sets × 10 reps            │
│                                 │
│  6️⃣ Plank                       │
│     3 sets × 30 sec             │
│                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━  │
│                                 │
│  [  Start This Workout  ]       │
│                                 │
│  [ Save to My Templates ]       │
│                                 │
└─────────────────────────────────┘
```

### Filter & Search Features

**Top of template browser:**
```
┌─────────────────────────────────┐
│  🔍 Search templates...         │
├─────────────────────────────────┤
│  Filters:                       │
│  [Duration ▼] [Equipment ▼]     │
│  [Difficulty ▼] [Muscle ▼]      │
└─────────────────────────────────┘
```

**Filter Options:**
- **Duration:** <30 min, 30-45 min, 45-60 min, 60+ min
- **Equipment:** Bodyweight, Dumbbells, Barbell, Machines, Cables, etc.
- **Difficulty:** 1-5 stars
- **Muscle Groups:** Chest, Back, Legs, Shoulders, Arms, Core, Full Body

---

## File Structure

### New Files to Create

```
WorkingOut/
├── Data/
│   └── BuiltInTemplates.swift (NEW - Template definitions)
├── Models/
│   └── WorkoutTemplate.swift (UPDATE - Add new properties)
├── Features/
│   └── Workouts/
│       ├── WorkoutLogView.swift (UPDATE - New + button flow)
│       ├── WorkoutStartChoiceView.swift (NEW)
│       ├── TemplateLibraryView.swift (NEW)
│       ├── ExperienceLevelView.swift (NEW)
│       ├── GoalSelectionView.swift (NEW)
│       ├── TemplateListByGoalView.swift (NEW)
│       ├── TemplateDetailView.swift (UPDATE - Enhance existing)
│       └── TemplateFilterView.swift (NEW)
└── Services/
    ├── WorkoutTemplateService.swift (UPDATE - Add library methods)
    └── TemplateSeeder.swift (NEW - Seed built-in templates)
```

---

## Data Structure

### BuiltInTemplates.swift Structure

```swift
struct BuiltInTemplate {
    let id: String
    let experienceLevel: ExperienceLevel
    let goal: WorkoutGoal
    let title: String
    let description: String
    let estimatedDuration: Int // minutes
    let difficulty: Int // 1-5
    let equipment: [Equipment]
    let muscleGroups: [MuscleGroup]
    let exercises: [TemplateExerciseData]
    let tags: [String]
}

struct TemplateExerciseData {
    let name: String
    let sets: Int
    let reps: Int
    let suggestedWeight: Double?
    let weightUnit: String
    let notes: String?
    let order: Int
}

enum ExperienceLevel: String, CaseIterable {
    case beginner = "Beginner"
    case intermediate = "Intermediate"
    case advanced = "Advanced"
}

enum WorkoutGoal: String {
    // Beginner
    case fullBodyFoundation = "Full Body Foundation"
    case weightLossStarter = "Weight Loss Starter"
    case mobilityRecovery = "Mobility & Recovery"
    case homeWorkoutBasics = "Home Workout Basics"
    case gymOrientation = "Gym Orientation"
    case coreStrength = "Core Strength"
    case bodyweightMastery = "Bodyweight Mastery"
    
    // Intermediate
    case muscleBuilding = "Muscle Building"
    case strengthGains = "Strength Gains"
    case athleticPerformance = "Athletic Performance"
    case fatLossToning = "Fat Loss & Toning"
    case upperBodyFocus = "Upper Body Focus"
    case lowerBodyPower = "Lower Body Power"
    case pushPullLegs = "Push/Pull/Legs Split"
    case functionalFitness = "Functional Fitness"
    
    // Advanced
    case powerlifting = "Powerlifting"
    case bodybuilding = "Bodybuilding"
    case olympicLifting = "Olympic Lifting"
    case enduranceStrength = "Endurance Strength"
    case hybridAthlete = "Hybrid Athlete"
    case specialization = "Specialization"
    case peakPerformance = "Peak Performance"
    case volumeTraining = "Volume Training"
}

enum Equipment: String {
    case barbell, dumbbells, kettlebell, bench, squat rack
    case pullupBar, dipStation, cables, machines
    case bodyweight, bands, medicineBall, box, ropes
    case sled, tire, sandbag, rings, skiErg, rower
    case assaultBike, foamRoller, yogaMat
}

enum MuscleGroup: String {
    case chest, back, shoulders, biceps, triceps, forearms
    case quads, hamstrings, glutes, calves
    case abs, obliques, lowerBack
    case fullBody
}
```

---

## Implementation Checklist

### Phase 1: Data & Models (4-6 hours)
- [ ] Update `WorkoutTemplate` model with new properties
- [ ] Create `BuiltInTemplates.swift` with all template definitions
- [ ] Create enums for ExperienceLevel, WorkoutGoal, Equipment, MuscleGroup
- [ ] Create `TemplateSeeder.swift` service
- [ ] Test data structures

### Phase 2: Template Library Service (3-4 hours)
- [ ] Add methods to `WorkoutTemplateService` for:
  - [ ] Load built-in templates
  - [ ] Filter by experience level
  - [ ] Filter by goal
  - [ ] Search templates
  - [ ] Get template by ID
- [ ] Create seeding logic (one-time on app launch)
- [ ] Test service methods

### Phase 3: UI Components (8-10 hours)
- [ ] Create `WorkoutStartChoiceView` (template vs blank)
- [ ] Create `TemplateLibraryView` (root navigation)
- [ ] Create `ExperienceLevelView` (level selection)
- [ ] Create `GoalSelectionView` (goal selection per level)
- [ ] Create `TemplateListByGoalView` (templates for a goal)
- [ ] Update `TemplateDetailView` (enhance with new data)
- [ ] Create `TemplateFilterView` (duration, equipment, etc.)
- [ ] Design template cards with badges
- [ ] Add difficulty stars UI component
- [ ] Add equipment icons

### Phase 4: Navigation Flow (2-3 hours)
- [ ] Update `WorkoutLogView` + button action
- [ ] Wire up navigation from start choice → library
- [ ] Wire up library → level → goal → template → detail
- [ ] Handle "start workout" from template detail
- [ ] Handle "save to my templates" feature
- [ ] Test full navigation flow

### Phase 5: Search & Filters (3-4 hours)
- [ ] Implement search bar functionality
- [ ] Create filter UI
- [ ] Implement duration filter
- [ ] Implement equipment filter
- [ ] Implement difficulty filter
- [ ] Implement muscle group filter
- [ ] Test filtering logic

### Phase 6: Template Seeding (2-3 hours)
- [ ] Create migration/seeding logic
- [ ] Seed all 130+ templates on first launch
- [ ] Add flag to prevent re-seeding
- [ ] Handle template updates (future versions)
- [ ] Test seeding performance

### Phase 7: Polish & UX (3-4 hours)
- [ ] Add empty states
- [ ] Add loading indicators
- [ ] Add animations/transitions
- [ ] Add helpful tips/descriptions
- [ ] Ensure consistent theming
- [ ] Test on iPhone and iPad
- [ ] Accessibility improvements

### Phase 8: Testing (3-4 hours)
- [ ] Test all experience levels
- [ ] Test all goals
- [ ] Test all template details
- [ ] Test starting workouts from templates
- [ ] Test search functionality
- [ ] Test all filters
- [ ] Test with no internet (all local)
- [ ] Performance test with full library

---

## Estimated Timeline

| Phase | Description | Time Estimate |
|-------|-------------|---------------|
| 1 | Data & Models | 4-6 hours |
| 2 | Template Service | 3-4 hours |
| 3 | UI Components | 8-10 hours |
| 4 | Navigation Flow | 2-3 hours |
| 5 | Search & Filters | 3-4 hours |
| 6 | Template Seeding | 2-3 hours |
| 7 | Polish & UX | 3-4 hours |
| 8 | Testing | 3-4 hours |
| **TOTAL** | | **28-38 hours** |

---

## Summary Statistics

### Template Library Content:
- **3 Experience Levels**
- **23 Total Goals** (7 beginner + 8 intermediate + 8 advanced)
- **130+ Built-in Templates**
- **Beginner:** 35 templates across 7 goals
- **Intermediate:** 48 templates across 8 goals
- **Advanced:** 50 templates across 8 goals

### Features:
- ✅ Experience-based organization
- ✅ Goal-based categorization
- ✅ Detailed exercise instructions
- ✅ Equipment requirements
- ✅ Duration estimates
- ✅ Difficulty ratings
- ✅ Muscle group targeting
- ✅ Search functionality
- ✅ Multiple filter options
- ✅ Custom template saving

---

*Implementation Plan for Pace & Plates - Workout Template Library*
*Date: October 29, 2025*
*Status: Ready for implementation - awaiting approval*

