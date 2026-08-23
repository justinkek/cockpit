# Showcase Screen Template

Disclosed reference for the `figma-to-component` skill. Contains the initial scaffold for the component showcase screen and the pattern for adding new component sections.

The examples below are React Native with spatial (D-pad) navigation, because that is where the pattern was first used. The **structure** is what carries over, not the imports: a scrollable screen, one section per component, one column per variant, each labelled. Substitute the project's own screen wrapper, scroll primitive and focus wrapper - named `<ScreenWrapper>`, `<ScrollView>` and `<FocusWrapper>` here - and drop the focus column entirely on platforms where focus is not a visual state.

## Initial scaffold

Create these files when the showcase screen does not yet exist.

### `<feature location>/showcase/ShowcaseScreen.tsx`

```tsx
import { FC } from "react";
import { Text, View } from "react-native";
import { ScrollView } from "<project scroll primitive>";
import { ScreenWrapper } from "<project screen wrapper>";
import { styles } from "./ShowcaseScreen.styles";

export const ShowcaseScreen: FC = () => {
  return (
    <ScreenWrapper>
      <View style={styles.screen}>
        <Text style={styles.title}>Component Showcase</Text>
        <ScrollView>
          <View style={styles.content}>{/* Component sections go here */}</View>
        </ScrollView>
      </View>
    </ScreenWrapper>
  );
};
```

### `<feature location>/showcase/ShowcaseScreen.styles.ts`

Use the project's own theme tokens - the token names below are illustrative. Pick a screen background that is distinguishable from the component containers, or variants with their own background will be invisible against it.

```tsx
import { StyleSheet } from "react-native";
import { colors } from "<theme>/colors";
import { typography } from "<theme>/typography";
import { spacing } from "<theme>/spacing";

export const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.backgroundNorm,
    padding: spacing.s32,
  },
  title: {
    ...typography.headlineBold,
    color: colors.textNorm,
    marginBottom: spacing.s32,
  },
  content: {
    gap: spacing.s48,
  },
  sectionTitle: {
    ...typography.bodyBold,
    color: colors.textWeak,
    marginBottom: spacing.s16,
  },
  row: {
    flexDirection: "row",
    gap: spacing.s24,
    alignItems: "flex-start",
  },
  variantWrapper: {
    alignItems: "center",
    gap: spacing.s8,
  },
  variantLabel: {
    ...typography.caption,
    color: colors.textWeak,
  },
});
```

### Navigation registration

Register `Showcase` in the project's route types, then add the screen to the navigator. The specific file depends on the navigation setup - find where the other screens are registered and follow it.

## Adding a component section

For each new component, add a section inside the `content` view:

```tsx
<View>
  <Text style={styles.sectionTitle}>ComponentName</Text>
  <View style={styles.row}>
    {/* Rest state - no focus wrapper */}
    <View style={styles.variantWrapper}>
      <ComponentName variant="rest" />
      <Text style={styles.variantLabel}>Rest</Text>
    </View>

    {/* Focused state - wrapped so the focused styles apply */}
    <View style={styles.variantWrapper}>
      <FocusWrapper>{() => <ComponentName variant="focused" />}</FocusWrapper>
      <Text style={styles.variantLabel}>Focused</Text>
    </View>
  </View>
</View>
```

For components with multiple variant axes (e.g. `selected` x `free`), add one row per axis combination:

```tsx
<View>
  <Text style={styles.sectionTitle}>CountryTile</Text>

  <Text style={styles.variantLabel}>Selected + Free</Text>
  <View style={styles.row}>
    <View style={styles.variantWrapper}>
      <CountryTile selected free />
      <Text style={styles.variantLabel}>Rest</Text>
    </View>
    <View style={styles.variantWrapper}>
      <FocusWrapper>{() => <CountryTile selected free />}</FocusWrapper>
      <Text style={styles.variantLabel}>Focused</Text>
    </View>
  </View>

  <Text style={styles.variantLabel}>Not Selected + Not Free</Text>
  <View style={styles.row}>{/* ... same pattern for each combination */}</View>
</View>
```

## Temporary initial route override

During validation, set the showcase as the initial route so the app opens directly to it:

```tsx
<Stack.Navigator initialRouteName="Showcase">
```

Revert after validation completes (step 8 of the skill).
