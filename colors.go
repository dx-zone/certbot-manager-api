// colors.go
package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/mattn/go-isatty" // Importing the isatty package to check if the output is a terminal
)

// ANSI escape codes for colored output
const (
	Reset         = "\033[0m"
	White         = "\033[37m"
	Red           = "\033[31m"
	Green         = "\033[32m"
	Yellow        = "\033[33m"
	Blue          = "\033[34m"
	Purple        = "\033[35m"
	Cyan          = "\033[36m"
	Pink          = "\033[95m"
	Bold          = "\033[1m"
	Underline     = "\033[4m"
	Strikethrough = "\033[9m"
	Faint         = "\033[2m" // Add this one for dimmed text (faint)
)

// NoColor is the global switch. We check the Terminal status AND the environment variable.
var NoColor = !isatty.IsTerminal(os.Stdout.Fd()) || os.Getenv("NO_COLOR") != ""

// Color is a custom type for colored strings
type Color string

// format applies the given ANSI code to the Color string, ensuring that it resets properly
// If NoColor is true, it returns the original Color without formatting
// It also ensures that if the Color already has formatting, it will be wrapped correctly without nesting issues
func (c Color) format(code string) Color {
	if NoColor {
		return c
	}
	clean := strings.TrimSuffix(string(c), Reset)
	return Color(code + clean + Reset)
}

func (c Color) White() Color {
	return c.format(White)
}

func (c Color) Red() Color {
	return c.format(Red)
}

func (c Color) Green() Color {
	return c.format(Green)
}

func (c Color) Yellow() Color {
	return c.format(Yellow)
}

func (c Color) Blue() Color {
	return c.format(Blue)
}

func (c Color) Purple() Color {
	return c.format(Purple)
}

func (c Color) Cyan() Color {
	return c.format(Cyan)
}

func (c Color) Bold() Color {
	return c.format(Bold)
}

func (c Color) Underline() Color {
	return c.format(Underline)
}

func (c Color) Strikethrough() Color {
	return c.format(Strikethrough)
}

// Faint applies the faint (dimmed) formatting to the Color string, making it appear less prominent in the terminal output. This is useful for de-emphasizing certain text, such as default values or less important information, while still keeping it visible.
// It uses the ANSI escape code for faint text and ensures that it resets properly after the formatted text. If NoColor is true, it returns the original Color without formatting.
func (c Color) Faint() Color {
	return c.format(Faint)
}

// color is a helper function to print colored text directly to the terminal
// It uses the Color type to apply the desired color formatting to the text and ensures that it resets properly after printing. This function is useful for quickly printing colored text to the terminal without needing to create a Color instance first.
func color(text string, colorName string) {
	fmt.Printf("%s%s%s\n", colorName, text, Reset)
}

// paint is a helper function to return a colored string without printing it directly
// It uses the Color type to apply the desired color formatting to the text and ensures that it resets properly after the formatted text. This function is useful for creating colored strings that can be used in various contexts, such as within other formatted output or when building complex strings with multiple colors.
func paint(text string, colorName string) string {
	return fmt.Sprintf("%s%s%s", colorName, text, Reset)
}

// printFlag is a helper function to print a command-line flag with its description and default value in a formatted manner
// It uses the Color type to apply different colors and formatting to the flag name, description, and default value for better readability in the terminal output. The flag name is printed in bold white, the description is printed in the default color, and the default value is printed in faint yellow to indicate that it is less prominent information.
func printFlag(name, desc, defaultValue string) {
	fmt.Fprintf(os.Stderr, "  %s  %-40s %s %s\n",
		Color(name).Bold().White(),
		desc,
		Color("(default:").Faint(),
		Color(defaultValue+")").Faint().Yellow(),
	)
}

/*
func main() {
	/*
		// Demonstrating the use of color functions and Color type
		// Example usage of the Color type and color functions
		file := paint("certificates.csv", Yellow)
		colorizedFile := Color("certificates.csv").Yellow()

		fmt.Println(Color("Reading CSV file:").White(), file)
		fmt.Println("File read successfully:", Color(file).Red())
		fmt.Println(Color("File read successfully:").Green(), Color(file).Green())

		// Example usage of color function
		color("Printing in 'Yellow'", Yellow)

		// Example usage of paint function
		fmt.Println(paint("Printing colors 'Pink'", Pink), "and 'Cyan'", paint("Cyan", Cyan))

		// Example usage of constant strings for colored output
		fmt.Printf("%s[FAIL]%s System disk full\n", Red, Reset)

		// Example usage of Color type with method chaining
		fmt.Println(Color(file).Bold().Red())

		// Printing the file name in different colors using the Color type
		fmt.Println("This is the file:", colorizedFile)

*/

/*

	// Filename to open
	file := "certificates.csv"

	// Attempt to read the CSV file and print the result
	fileStat, err := readCSV(file)
	if err != nil {
		fmt.Printf("Failed to read file: %v\n", Color(err.Error()).Red())
	} else {
		fmt.Printf("File %s found, is directory: %v\n", Color(file).Green(), fileStat)
	}
}
*/

/*
// TODO: readCSV read the CSV file and return a slice of records
func readCSV(filePath string) (bool, error) {
	// Implement CSV reading logic here
	fileInfo, err := os.Stat(filePath)
	if err != nil {
		return false, err
	} else {
		return fileInfo.IsDir(), nil
	}
}
*/
