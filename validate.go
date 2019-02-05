package main

import (
	"fmt"
	"log"

	"github.com/forj-oss/goforjj"
)

func (a *Forj) validateAction(string) {
	if err := a.Validate(); err != nil {
		log.Fatalf("Forjj validate issue. %s", err)
	}
}

// Validate check forjfile rules and return an error is the Forjfile loaded is respecting those rules.
func (a *Forj) Validate() error {
	return a.ValidateForjfile()
}

// FoundValidAppFlag return true if the flag checked has been defined by the plugin.
// if not an error is returned.
func (a *Forj) FoundValidAppFlag(key, driver, object string, required bool) (_ bool, err error) {
	d, _ := a.drivers.Get(driver)
	if d == nil {
		err = fmt.Errorf("Internal issue. Driver %s not found in memory", driver)
		return
	}

	if d.Plugin == nil {
		err = fmt.Errorf("No %s driver '%s' loaded for application '%s'", d.DriverType, d.Name, driver)
		return
	}

	if o, found := d.Plugin.Yaml.Objects[object]; found {
		return o.HasValidKey(key), nil
	}
	if required {
		err = fmt.Errorf("Plugin %s issue. objects/'%s' has not been defined in the plugin. Contact Plugin maintainer", driver, object)
	}
	return
}

// ValidateForjfile read all object fields and check if they are recognized by forjj or plugins.
func (a *Forj) ValidateForjfile() (_ error) {
	f := a.f.DeployForjfile()

	if err := a.f.Validate(); err != nil {
		return fmt.Errorf("Validation error. %s", err)
	}

	// AppYamlStruct.More
	for _, app := range f.Apps {
		for key := range app.More {
			if found, err := a.FoundValidAppFlag(key, app.Driver, goforjj.ObjectApp, true); err != nil {
				return err
			} else if !found {
				return fmt.Errorf("'%s' has no effect. No drivers use it", key)
			}
		}
	}

	fmt.Print("Validated successfully.\n")
	return
}
