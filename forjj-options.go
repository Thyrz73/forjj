package main

import (
	"github.com/forj-oss/forjj-modules/trace"
)

const (
	forjj_options_file = "Forjfile.yml"
)

// This data structure is going to be saved in the infra repository anytime a global update is done.
type ForjjOptions struct {
	Defaults map[string]string
	//Drivers  map[string]*drivers.Driver
}

func (a *Forj) GetUniqDriverName(driverType string) (od string) {
	var found_one_driver *string

	for instance, d := range a.drivers.List() {
		if d.DriverType == driverType {
			switch {
			case found_one_driver == nil:
				found_one_driver = &od
				od = instance
			case *found_one_driver != "":
				od = ""
			}
		}
	}
	switch {
	case found_one_driver == nil:
		gotrace.Trace("No %s instance found.", driverType)
	case *found_one_driver == "":
		gotrace.Trace("Too many %s instances found.", driverType)
	default:
		gotrace.Trace("One upstream instance found: %s", *found_one_driver)
	}
	return
}

// SetDefault Forjj-option: Set default
// - instance
// - flow
func (a *Forj) SetDefault(action string) {
	if od := a.GetUniqDriverName("upstream"); od != "" {
		a.o.Defaults["instance"] = od
	}

	// Set Defaults for repositories.
	if v, found, _, _ := a.cli.GetStringValue(infra, "", flow_obj); found && v != "" {
		a.o.Defaults[flow_obj] = v
	}
}

// LoadForge loads the forjj options definitions from the LoadContext().
func (a *Forj) LoadForge() (err error) {
	if v := a.forjfile_tmpl_path; v != "" && a.w.InfraPath() == v {
		gotrace.Info("If your Forfile template has defined local settings and/or credentials data, those data will " +
			"be moved to the internal forjj workspace.")
		return
	}

	deployTo, _, _ := a.GetPrefs(deployToArg) // cli or Forjfile(empty) or cli default

	_, err = a.f.Load(deployTo)

	return
}
