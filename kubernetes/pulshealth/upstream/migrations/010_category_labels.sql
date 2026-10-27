-- puls:rerun
-- Human-readable labels for HKCategorySample.value.
-- Seeded from the iPhoneOS 26.5 HealthKit headers:
-- HKTypeIdentifiers.h maps category identifiers to value enums, and
-- HKCategoryValues.h defines the enum values.
--
-- Marked puls:rerun: the seed is refreshed in place after SDK updates and the
-- INSERT below is an upsert, so the migrate service re-applies this file
-- whenever it changes instead of requiring a new numbered copy of the seed.

CREATE TABLE IF NOT EXISTS category_labels (
    type_identifier text     NOT NULL,
    value           smallint NOT NULL,
    enum_name       text     NOT NULL,
    label           text     NOT NULL,
    is_deprecated   boolean  NOT NULL DEFAULT false,
    PRIMARY KEY (type_identifier, value)
);

WITH
generic_types(type_identifier) AS (
    VALUES
        ('HKCategoryTypeIdentifierHandwashingEvent'),
        ('HKCategoryTypeIdentifierHighHeartRateEvent'),
        ('HKCategoryTypeIdentifierHypertensionEvent'),
        ('HKCategoryTypeIdentifierInfrequentMenstrualCycles'),
        ('HKCategoryTypeIdentifierIntermenstrualBleeding'),
        ('HKCategoryTypeIdentifierIrregularHeartRhythmEvent'),
        ('HKCategoryTypeIdentifierIrregularMenstrualCycles'),
        ('HKCategoryTypeIdentifierLactation'),
        ('HKCategoryTypeIdentifierLowHeartRateEvent'),
        ('HKCategoryTypeIdentifierMindfulSession'),
        ('HKCategoryTypeIdentifierPersistentIntermenstrualBleeding'),
        ('HKCategoryTypeIdentifierPregnancy'),
        ('HKCategoryTypeIdentifierProlongedMenstrualPeriods'),
        ('HKCategoryTypeIdentifierSexualActivity'),
        ('HKCategoryTypeIdentifierSleepApneaEvent'),
        ('HKCategoryTypeIdentifierToothbrushingEvent')
),
severity_types(type_identifier) AS (
    VALUES
        ('HKCategoryTypeIdentifierAbdominalCramps'),
        ('HKCategoryTypeIdentifierAcne'),
        ('HKCategoryTypeIdentifierBladderIncontinence'),
        ('HKCategoryTypeIdentifierBloating'),
        ('HKCategoryTypeIdentifierBreastPain'),
        ('HKCategoryTypeIdentifierChestTightnessOrPain'),
        ('HKCategoryTypeIdentifierChills'),
        ('HKCategoryTypeIdentifierConstipation'),
        ('HKCategoryTypeIdentifierCoughing'),
        ('HKCategoryTypeIdentifierDiarrhea'),
        ('HKCategoryTypeIdentifierDizziness'),
        ('HKCategoryTypeIdentifierDrySkin'),
        ('HKCategoryTypeIdentifierFainting'),
        ('HKCategoryTypeIdentifierFatigue'),
        ('HKCategoryTypeIdentifierFever'),
        ('HKCategoryTypeIdentifierGeneralizedBodyAche'),
        ('HKCategoryTypeIdentifierHairLoss'),
        ('HKCategoryTypeIdentifierHeadache'),
        ('HKCategoryTypeIdentifierHeartburn'),
        ('HKCategoryTypeIdentifierHotFlashes'),
        ('HKCategoryTypeIdentifierLossOfSmell'),
        ('HKCategoryTypeIdentifierLossOfTaste'),
        ('HKCategoryTypeIdentifierLowerBackPain'),
        ('HKCategoryTypeIdentifierMemoryLapse'),
        ('HKCategoryTypeIdentifierNausea'),
        ('HKCategoryTypeIdentifierNightSweats'),
        ('HKCategoryTypeIdentifierPelvicPain'),
        ('HKCategoryTypeIdentifierRapidPoundingOrFlutteringHeartbeat'),
        ('HKCategoryTypeIdentifierRunnyNose'),
        ('HKCategoryTypeIdentifierShortnessOfBreath'),
        ('HKCategoryTypeIdentifierSinusCongestion'),
        ('HKCategoryTypeIdentifierSkippedHeartbeat'),
        ('HKCategoryTypeIdentifierSoreThroat'),
        ('HKCategoryTypeIdentifierVaginalDryness'),
        ('HKCategoryTypeIdentifierVomiting'),
        ('HKCategoryTypeIdentifierWheezing')
),
vaginal_bleeding_types(type_identifier) AS (
    VALUES
        ('HKCategoryTypeIdentifierBleedingAfterPregnancy'),
        ('HKCategoryTypeIdentifierBleedingDuringPregnancy'),
        ('HKCategoryTypeIdentifierMenstrualFlow')
),
presence_types(type_identifier) AS (
    VALUES
        ('HKCategoryTypeIdentifierMoodChanges'),
        ('HKCategoryTypeIdentifierSleepChanges')
),
labels(type_identifier, value, enum_name, label, is_deprecated) AS (
    SELECT type_identifier, 0::smallint, 'HKCategoryValueNotApplicable', 'Not Applicable', false
    FROM generic_types

    UNION ALL
    SELECT type_identifier, value, enum_name, label, false
    FROM severity_types
    CROSS JOIN (VALUES
        (0::smallint, 'HKCategoryValueSeverityUnspecified', 'Unspecified'),
        (1::smallint, 'HKCategoryValueSeverityNotPresent', 'Not Present'),
        (2::smallint, 'HKCategoryValueSeverityMild', 'Mild'),
        (3::smallint, 'HKCategoryValueSeverityModerate', 'Moderate'),
        (4::smallint, 'HKCategoryValueSeveritySevere', 'Severe')
    ) AS severity_values(value, enum_name, label)

    UNION ALL
    SELECT type_identifier, value, enum_name, label, false
    FROM vaginal_bleeding_types
    CROSS JOIN (VALUES
        (1::smallint, 'HKCategoryValueVaginalBleedingUnspecified', 'Unspecified'),
        (2::smallint, 'HKCategoryValueVaginalBleedingLight', 'Light'),
        (3::smallint, 'HKCategoryValueVaginalBleedingMedium', 'Medium'),
        (4::smallint, 'HKCategoryValueVaginalBleedingHeavy', 'Heavy'),
        (5::smallint, 'HKCategoryValueVaginalBleedingNone', 'None')
    ) AS vaginal_bleeding_values(value, enum_name, label)

    UNION ALL
    SELECT type_identifier, value, enum_name, label, false
    FROM presence_types
    CROSS JOIN (VALUES
        (0::smallint, 'HKCategoryValuePresencePresent', 'Present'),
        (1::smallint, 'HKCategoryValuePresenceNotPresent', 'Not Present')
    ) AS presence_values(value, enum_name, label)

    UNION ALL
    VALUES
        ('HKCategoryTypeIdentifierAppetiteChanges', 0::smallint, 'HKCategoryValueAppetiteChangesUnspecified', 'Unspecified', false),
        ('HKCategoryTypeIdentifierAppetiteChanges', 1::smallint, 'HKCategoryValueAppetiteChangesNoChange', 'No Change', false),
        ('HKCategoryTypeIdentifierAppetiteChanges', 2::smallint, 'HKCategoryValueAppetiteChangesDecreased', 'Decreased', false),
        ('HKCategoryTypeIdentifierAppetiteChanges', 3::smallint, 'HKCategoryValueAppetiteChangesIncreased', 'Increased', false),

        ('HKCategoryTypeIdentifierAppleStandHour', 0::smallint, 'HKCategoryValueAppleStandHourStood', 'Stood', false),
        ('HKCategoryTypeIdentifierAppleStandHour', 1::smallint, 'HKCategoryValueAppleStandHourIdle', 'Idle', false),

        ('HKCategoryTypeIdentifierAppleWalkingSteadinessEvent', 1::smallint, 'HKCategoryValueAppleWalkingSteadinessEventInitialLow', 'Initial Low', false),
        ('HKCategoryTypeIdentifierAppleWalkingSteadinessEvent', 2::smallint, 'HKCategoryValueAppleWalkingSteadinessEventInitialVeryLow', 'Initial Very Low', false),
        ('HKCategoryTypeIdentifierAppleWalkingSteadinessEvent', 3::smallint, 'HKCategoryValueAppleWalkingSteadinessEventRepeatLow', 'Repeat Low', false),
        ('HKCategoryTypeIdentifierAppleWalkingSteadinessEvent', 4::smallint, 'HKCategoryValueAppleWalkingSteadinessEventRepeatVeryLow', 'Repeat Very Low', false),

        -- HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent (iOS 14) kept
        -- the raw value of the iOS 13 constant it replaced, so this — not the
        -- newer constant's spelling — is the identifier samples actually carry.
        ('HKCategoryTypeIdentifierAudioExposureEvent', 1::smallint, 'HKCategoryValueEnvironmentalAudioExposureEventMomentaryLimit', 'Momentary Limit', false),

        ('HKCategoryTypeIdentifierCervicalMucusQuality', 1::smallint, 'HKCategoryValueCervicalMucusQualityDry', 'Dry', false),
        ('HKCategoryTypeIdentifierCervicalMucusQuality', 2::smallint, 'HKCategoryValueCervicalMucusQualitySticky', 'Sticky', false),
        ('HKCategoryTypeIdentifierCervicalMucusQuality', 3::smallint, 'HKCategoryValueCervicalMucusQualityCreamy', 'Creamy', false),
        ('HKCategoryTypeIdentifierCervicalMucusQuality', 4::smallint, 'HKCategoryValueCervicalMucusQualityWatery', 'Watery', false),
        ('HKCategoryTypeIdentifierCervicalMucusQuality', 5::smallint, 'HKCategoryValueCervicalMucusQualityEggWhite', 'Egg White', false),

        ('HKCategoryTypeIdentifierContraceptive', 1::smallint, 'HKCategoryValueContraceptiveUnspecified', 'Unspecified', false),
        ('HKCategoryTypeIdentifierContraceptive', 2::smallint, 'HKCategoryValueContraceptiveImplant', 'Implant', false),
        ('HKCategoryTypeIdentifierContraceptive', 3::smallint, 'HKCategoryValueContraceptiveInjection', 'Injection', false),
        ('HKCategoryTypeIdentifierContraceptive', 4::smallint, 'HKCategoryValueContraceptiveIntrauterineDevice', 'Intrauterine Device', false),
        ('HKCategoryTypeIdentifierContraceptive', 5::smallint, 'HKCategoryValueContraceptiveIntravaginalRing', 'Intravaginal Ring', false),
        ('HKCategoryTypeIdentifierContraceptive', 6::smallint, 'HKCategoryValueContraceptiveOral', 'Oral', false),
        ('HKCategoryTypeIdentifierContraceptive', 7::smallint, 'HKCategoryValueContraceptivePatch', 'Patch', false),

        ('HKCategoryTypeIdentifierHeadphoneAudioExposureEvent', 1::smallint, 'HKCategoryValueHeadphoneAudioExposureEventSevenDayLimit', 'Seven Day Limit', false),
        ('HKCategoryTypeIdentifierLowCardioFitnessEvent', 1::smallint, 'HKCategoryValueLowCardioFitnessEventLowFitness', 'Low Fitness', false),

        ('HKCategoryTypeIdentifierOvulationTestResult', 1::smallint, 'HKCategoryValueOvulationTestResultNegative', 'Negative', false),
        ('HKCategoryTypeIdentifierOvulationTestResult', 2::smallint, 'HKCategoryValueOvulationTestResultLuteinizingHormoneSurge', 'Luteinizing Hormone Surge', false),
        ('HKCategoryTypeIdentifierOvulationTestResult', 3::smallint, 'HKCategoryValueOvulationTestResultIndeterminate', 'Indeterminate', false),
        ('HKCategoryTypeIdentifierOvulationTestResult', 4::smallint, 'HKCategoryValueOvulationTestResultEstrogenSurge', 'Estrogen Surge', false),

        ('HKCategoryTypeIdentifierPregnancyTestResult', 1::smallint, 'HKCategoryValuePregnancyTestResultNegative', 'Negative', false),
        ('HKCategoryTypeIdentifierPregnancyTestResult', 2::smallint, 'HKCategoryValuePregnancyTestResultPositive', 'Positive', false),
        ('HKCategoryTypeIdentifierPregnancyTestResult', 3::smallint, 'HKCategoryValuePregnancyTestResultIndeterminate', 'Indeterminate', false),

        ('HKCategoryTypeIdentifierProgesteroneTestResult', 1::smallint, 'HKCategoryValueProgesteroneTestResultNegative', 'Negative', false),
        ('HKCategoryTypeIdentifierProgesteroneTestResult', 2::smallint, 'HKCategoryValueProgesteroneTestResultPositive', 'Positive', false),
        ('HKCategoryTypeIdentifierProgesteroneTestResult', 3::smallint, 'HKCategoryValueProgesteroneTestResultIndeterminate', 'Indeterminate', false),

        ('HKCategoryTypeIdentifierSleepAnalysis', 0::smallint, 'HKCategoryValueSleepAnalysisInBed', 'In Bed', false),
        ('HKCategoryTypeIdentifierSleepAnalysis', 1::smallint, 'HKCategoryValueSleepAnalysisAsleepUnspecified', 'Asleep Unspecified', false),
        ('HKCategoryTypeIdentifierSleepAnalysis', 2::smallint, 'HKCategoryValueSleepAnalysisAwake', 'Awake', false),
        ('HKCategoryTypeIdentifierSleepAnalysis', 3::smallint, 'HKCategoryValueSleepAnalysisAsleepCore', 'Asleep Core', false),
        ('HKCategoryTypeIdentifierSleepAnalysis', 4::smallint, 'HKCategoryValueSleepAnalysisAsleepDeep', 'Asleep Deep', false),
        ('HKCategoryTypeIdentifierSleepAnalysis', 5::smallint, 'HKCategoryValueSleepAnalysisAsleepREM', 'Asleep REM', false)
)
INSERT INTO category_labels (type_identifier, value, enum_name, label, is_deprecated)
SELECT type_identifier, value, enum_name, label, is_deprecated
FROM labels
ON CONFLICT (type_identifier, value) DO UPDATE
SET enum_name = EXCLUDED.enum_name,
    label = EXCLUDED.label,
    is_deprecated = EXCLUDED.is_deprecated;

-- Earlier revisions of this seed keyed loud-environment events on the iOS 14
-- constant's spelling. No sample can carry that string (see above), so the row
-- was unreachable; drop it wherever a previous run inserted it.
DELETE FROM category_labels
WHERE type_identifier = 'HKCategoryTypeIdentifierEnvironmentalAudioExposureEvent';
