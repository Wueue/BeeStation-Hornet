#define DEPT_ALL 0
#define DEPT_GEN 1
#define DEPT_SEC 2
#define DEPT_MED 3
#define DEPT_SCI 4
#define DEPT_ENG 5
#define DEPT_SUP 6

//Keeps track of the time for the ID console. Having it as a global variable prevents people from dismantling/reassembling it to
//increase the slots of many jobs.
GLOBAL_VAR_INIT(time_last_changed_position, 0)

/obj/machinery/computer/card
	name = "identification console"
	desc = "You can use this to manage jobs and ID access."
	icon_screen = "id"
	icon_keyboard = "id_key"
	req_one_access = list(ACCESS_HEADS, ACCESS_CHANGE_IDS)
	circuit = /obj/item/circuitboard/computer/card
	var/obj/item/card/id/scan = null
	var/obj/item/card/id/modify = null
	var/authenticated = 0
	var/mode = 0
	var/printing = null
	var/list/region_access = null
	var/list/head_subordinates = null
	var/target_dept = DEPT_ALL //Which department this computer has access to.

	//Cooldown for closing positions in seconds
	//if set to -1: No cooldown... probably a bad idea
	//if set to 0: Not able to close "original" positions. You can only close positions that you have opened before
	var/change_position_cooldown = 30
	//Jobs you cannot open new positions for
	var/list/blacklisted = list(
		"AI",
		"Assistant",
		"Cyborg",
		"Captain",
		"Head of Personnel",
		"Head of Security",
		"Chief Engineer",
		"Research Director",
		"Chief Medical Officer",
		"Brig Physician",
		"Deputy")

	//The scaling factor of max total positions in relation to the total amount of people on board the station in %
	var/max_relative_positions = 30 //30%: Seems reasonable, limit of 6 @ 20 players

	//This is used to keep track of opened positions for jobs to allow instant closing
	//Assoc array: "JobName" = (int)<Opened Positions>
	var/list/opened_positions = list();

	light_color = LIGHT_COLOR_BLUE

/obj/machinery/computer/card/examine(mob/user)
	. = ..()
	if(scan || modify)
		. += "<span class='notice'>Alt-click to eject the ID card.</span>"

/obj/machinery/computer/card/Initialize(mapload)
	. = ..()
	change_position_cooldown = CONFIG_GET(number/id_console_jobslot_delay)
	for(var/G in typesof(/datum/job/gimmick))
		var/datum/job/gimmick/J = new G
		blacklisted += J.title

/obj/machinery/computer/card/attackby(obj/O, mob/user, params)//TODO:SANITY
	if(istype(O, /obj/item/card/id))
		var/obj/item/card/id/idcard = O
		if(check_access(idcard))
			if(!scan)
				if (!user.transferItemToLoc(idcard,src))
					return
				scan = idcard
				playsound(src, 'sound/machines/terminal_insert_disc.ogg', 50, 0)
			else if(!modify)
				if (!user.transferItemToLoc(idcard,src))
					return
				modify = idcard
				playsound(src, 'sound/machines/terminal_insert_disc.ogg', 50, 0)
		else
			if(!modify)
				if (!user.transferItemToLoc(idcard,src))
					return
				modify = idcard
				playsound(src, 'sound/machines/terminal_insert_disc.ogg', 50, 0)
		updateUsrDialog()
	else
		return ..()

/obj/machinery/computer/card/Destroy()
	if(scan)
		qdel(scan)
		scan = null
	if(modify)
		qdel(modify)
		modify = null
	return ..()

/obj/machinery/computer/card/handle_atom_del(atom/A)
	..()
	if(A == scan)
		scan = null
		updateUsrDialog()
	if(A == modify)
		modify = null
		updateUsrDialog()

/obj/machinery/computer/card/on_deconstruction()
	if(scan)
		scan.forceMove(drop_location())
		scan = null
	if(modify)
		modify.forceMove(drop_location())
		modify = null

//Check if you can't open a new position for a certain job
/obj/machinery/computer/card/proc/job_blacklisted(jobtitle)
	return (jobtitle in blacklisted)


//Logic check for Topic() if you can open the job
/obj/machinery/computer/card/proc/can_open_job(datum/job/job)
	if(job)
		if(!job_blacklisted(job.title))
			if((job.total_positions <= GLOB.player_list.len * (max_relative_positions / 100)))
				var/delta = (world.time / 10) - GLOB.time_last_changed_position
				if((change_position_cooldown < delta) || (opened_positions[job.title] < 0))
					return 1
				return -2
			return -1
	return 0

//Logic check for Topic() if you can close the job
/obj/machinery/computer/card/proc/can_close_job(datum/job/job)
	if(job)
		if(!job_blacklisted(job.title))
			if(job.total_positions > job.current_positions)
				var/delta = (world.time / 10) - GLOB.time_last_changed_position
				if((change_position_cooldown < delta) || (opened_positions[job.title] > 0))
					return 1
				return -2
			return -1
	return 0

/obj/machinery/computer/card/ui_interact(mob/user)
	. = ..()

	var/dat
	if(!SSticker)
		return
	if (mode == 1) // accessing crew manifest
		var/crew = ""
		for(var/datum/data/record/t in sortRecord(GLOB.data_core.general))
			crew += t.fields["name"] + " - " + t.fields["rank"] + "<br>"
		dat = "<tt><b>Crew Manifest:</b><br>Please use security record computer to modify entries.<br><br>[crew]<a href='?src=[REF(src)];choice=print'>Print</a><br><br><a href='?src=[REF(src)];choice=mode;mode_target=0'>Access ID modification console.</a><br></tt>"

	else if(mode == 2)
		// JOB MANAGEMENT
		dat = "<a href='?src=[REF(src)];choice=return'>Return</a>"
		dat += " || Confirm Identity: "
		var/S
		if(scan)
			S = html_encode(scan.name)
		else
			S = "--------"
		dat += "<a href='?src=[REF(src)];choice=scan'>[S]</a>"
		dat += "<table>"
		dat += "<tr><td style='width:25%'><b>Job</b></td><td style='width:25%'><b>Slots</b></td><td style='width:25%'><b>Open job</b></td><td style='width:25%'><b>Close job</b><td style='width:25%'><b>Prioritize</b></td></td></tr>"
		var/ID
		if(scan && (ACCESS_CHANGE_IDS in scan.access) && !target_dept)
			ID = 1
		else
			ID = 0
		for(var/datum/job/job in SSjob.occupations)
			dat += "<tr>"
			if(job.title in blacklisted)
				continue
			dat += "<td>[job.title]</td>"
			dat += "<td>[job.current_positions]/[job.total_positions]</td>"
			dat += "<td>"
			switch(can_open_job(job))
				if(1)
					if(ID)
						dat += "<a href='?src=[REF(src)];choice=make_job_available;job=[job.title]'>Open Position</a><br>"
					else
						dat += "Open Position"
				if(-1)
					dat += "Denied"
				if(-2)
					var/time_to_wait = round(change_position_cooldown - ((world.time / 10) - GLOB.time_last_changed_position), 1)
					var/mins = round(time_to_wait / 60)
					var/seconds = time_to_wait - (60*mins)
					dat += "Cooldown ongoing: [mins]:[(seconds < 10) ? "0[seconds]" : "[seconds]"]"
				if(0)
					dat += "Denied"
			dat += "</td><td>"
			switch(can_close_job(job))
				if(1)
					if(ID)
						dat += "<a href='?src=[REF(src)];choice=make_job_unavailable;job=[job.title]'>Close Position</a>"
					else
						dat += "Close Position"
				if(-1)
					dat += "Denied"
				if(-2)
					var/time_to_wait = round(change_position_cooldown - ((world.time / 10) - GLOB.time_last_changed_position), 1)
					var/mins = round(time_to_wait / 60)
					var/seconds = time_to_wait - (60*mins)
					dat += "Cooldown ongoing: [mins]:[(seconds < 10) ? "0[seconds]" : "[seconds]"]"
				if(0)
					dat += "Denied"
			dat += "</td><td>"
			switch(job.total_positions)
				if(0)
					dat += "Denied"
				else
					if(ID)
						if(job in SSjob.prioritized_jobs)
							dat += "<a href='?src=[REF(src)];choice=prioritize_job;job=[job.title]'>Deprioritize</a>"
						else
							if(SSjob.prioritized_jobs.len < 5)
								dat += "<a href='?src=[REF(src)];choice=prioritize_job;job=[job.title]'>Prioritize</a>"
							else
								dat += "Denied"
					else
						dat += "Prioritize"

			dat += "</td></tr>"
		dat += "</table>"
	else if(mode == 3)
		//PAYCHECK MANAGEMENT
		dat = "<a href='?src=[REF(src)];choice=return'>Return</a>"
		dat += " || Confirm Identity: "
		var/S
		var/list/paycheck_departments = list()
		if(scan)
			S = html_encode(scan.name)
			//Checking all the accesses and their corresponding departments
			if((ACCESS_HOP in scan.access) && ((target_dept==DEPT_GEN) || !target_dept))
				paycheck_departments |= ACCOUNT_SRV
				paycheck_departments |= ACCOUNT_CIV
				paycheck_departments |= ACCOUNT_CAR //Currently no seperation between service/civillian and supply
			if((ACCESS_HOS in scan.access) && ((target_dept==DEPT_SEC) || !target_dept))
				paycheck_departments |= ACCOUNT_SEC
			if((ACCESS_CMO in scan.access) && ((target_dept==DEPT_MED) || !target_dept))
				paycheck_departments |= ACCOUNT_MED
			if((ACCESS_RD in scan.access) && ((target_dept==DEPT_SCI) || !target_dept))
				paycheck_departments |= ACCOUNT_SCI
			if((ACCESS_CE in scan.access) && ((target_dept==DEPT_ENG) || !target_dept))
				paycheck_departments |= ACCOUNT_ENG
		else
			S = "--------"
		dat += "<a href='?src=[REF(src)];choice=scan'>[S]</a>"
		dat += "<table>"
		dat += "<tr><td style='width:25%'><b>Name</b></td><td style='width:25%'><b>Job</b></td><td style='width:25%'><b>Paycheck</b></td><td style='width:25%'><b>Pay Bonus</b></td></tr>"

		for(var/A in SSeconomy.bank_accounts)
			var/datum/bank_account/B = A
			if(!(B.account_job.paycheck_department in paycheck_departments))
				continue
			dat += "<tr>"
			dat += "<td>[B.account_holder]</td>"
			dat += "<td>[B.account_job.title]</td>"
			dat += "<td><a href='?src=[REF(src)];choice=adjust_pay;account=[B.account_holder]'>$[B.paycheck_amount]</a></td>"
			dat += "<td><a href='?src=[REF(src)];choice=adjust_bonus;account=[B.account_holder]'>$[B.paycheck_bonus]</a></td>"
	else
		var/header = ""

		var/target_name
		var/target_owner
		var/target_rank
		if(modify)
			target_name = html_encode(modify.name)
		else
			target_name = "--------"
		if(modify?.registered_name)
			target_owner = html_encode(modify.registered_name)
		else
			target_owner = "--------"
		if(modify && modify.assignment)
			target_rank = html_encode(modify.assignment)
		else
			target_rank = "Unassigned"

		var/scan_name
		if(scan)
			scan_name = html_encode(scan.name)
		else
			scan_name = "--------"

		if(!authenticated)
			header += "<br><i>Please insert the cards into the slots</i><br>"
			header += "Target: <a href='?src=[REF(src)];choice=modify'>[target_name]</a><br>"
			header += "Confirm Identity: <a href='?src=[REF(src)];choice=scan'>[scan_name]</a><br>"
		else
			header += "<div align='center'><br>"
			header += "<a href='?src=[REF(src)];choice=modify'>Remove [target_name]</a> || "
			header += "<a href='?src=[REF(src)];choice=scan'>Remove [scan_name]</a> <br> "
			header += "<a href='?src=[REF(src)];choice=mode;mode_target=1'>Access Crew Manifest</a> <br> "
			header += "<a href='?src=[REF(src)];choice=logout'>Log Out</a></div>"

		header += "<hr>"

		var/jobs_all = ""
		var/list/alljobs = list("Unassigned")
		alljobs += (istype(src, /obj/machinery/computer/card/centcom)? get_all_centcom_jobs() : get_all_jobs()) + "Custom"
		for(var/job in alljobs)
			if(job == "Assistant")
				jobs_all += "<br/>* Service: "
			if(job == "Quartermaster")
				jobs_all += "<br/>* Cargo: "
			if(job == "Chief Engineer")
				jobs_all += "<br/>* Engineering: "
			if(job == "Research Director")
				jobs_all += "<br/>* R&D: "
			if(job == "Chief Medical Officer")
				jobs_all += "<br/>* Medical: "
			if(job == "Head of Security")
				jobs_all += "<br/>* Security: "
			if(job == "Custom")
				jobs_all += "<br/>"
			// these will make some separation for the department.
			jobs_all += "<a href='?src=[REF(src)];choice=assign;assign_target=[job]'>[replacetext(job, " ", "&nbsp")]</a> " //make sure there isn't a line break in the middle of a job


		var/body

		if (authenticated && modify)

			var/carddesc = text("")
			var/jobs = text("")
			if( authenticated == 2)
				carddesc += {"<script type="text/javascript">
									function markRed(){
										var nameField = document.getElementById('namefield');
										nameField.style.backgroundColor = "#FFDDDD";
									}
									function markGreen(){
										var nameField = document.getElementById('namefield');
										nameField.style.backgroundColor = "#DDFFDD";
									}
									function showAll(){
										var allJobsSlot = document.getElementById('alljobsslot');
										allJobsSlot.innerHTML = "<a href='#' onclick='hideAll()'>hide</a><br>"+ "[jobs_all]";
									}
									function hideAll(){
										var allJobsSlot = document.getElementById('alljobsslot');
										allJobsSlot.innerHTML = "<a href='#' onclick='showAll()'>show</a>";
									}
								</script>"}
				carddesc += "<form name='cardcomp' action='?src=[REF(src)]' method='get'>"
				carddesc += "<input type='hidden' name='src' value='[REF(src)]'>"
				carddesc += "<input type='hidden' name='choice' value='reg'>"
				carddesc += "<b>registered name:</b> <input type='text' id='namefield' name='reg' value='[target_owner]' style='width:250px; background-color:white;' onchange='markRed()'>"
				carddesc += "<input type='submit' value='Rename' onclick='markGreen()'>"
				carddesc += "</form>"
				carddesc += "<b>Assignment:</b> "

				jobs += "<span id='alljobsslot'><a href='#' onclick='showAll()'>[target_rank]</a></span>" //CHECK THIS

			else
				carddesc += "<b>registered_name:</b> [target_owner]</span>"
				jobs += "<b>Assignment:</b> [target_rank] (<a href='?src=[REF(src)];choice=demote'>Demote</a>)</span>"

			var/accesses = ""
			if(istype(src, /obj/machinery/computer/card/centcom))
				accesses += "<h5>Central Command:</h5>"
				for(var/A in get_all_centcom_access())
					if(A in modify.access)
						accesses += "<a href='?src=[REF(src)];choice=access;access_target=[A];allowed=0'><font color=\"red\">[replacetext(get_centcom_access_desc(A), " ", "&nbsp")]</font></a> "
					else
						accesses += "<a href='?src=[REF(src)];choice=access;access_target=[A];allowed=1'>[replacetext(get_centcom_access_desc(A), " ", "&nbsp")]</a> "
			else
				accesses += "<div align='center'><b>Access</b></div>"
				accesses += "<table style='width:100%'>"
				accesses += "<tr>"
				for(var/i = 1; i <= 7; i++)
					if(authenticated == 1 && !(i in region_access))
						continue
					accesses += "<td style='width:14%'><b>[get_region_accesses_name(i)]:</b></td>"
				accesses += "</tr><tr>"
				for(var/i = 1; i <= 7; i++)
					if(authenticated == 1 && !(i in region_access))
						continue
					accesses += "<td style='width:14%' valign='top'>"
					for(var/A in get_region_accesses(i))
						if(A in modify.access)
							accesses += "<a href='?src=[REF(src)];choice=access;access_target=[A];allowed=0'><font color=\"red\">[replacetext(get_access_desc(A), " ", "&nbsp")]</font></a> "
						else
							accesses += "<a href='?src=[REF(src)];choice=access;access_target=[A];allowed=1'>[replacetext(get_access_desc(A), " ", "&nbsp")]</a> "
						accesses += "<br>"
					accesses += "</td>"
				accesses += "</tr></table>"
			body = "[carddesc]<br>[jobs]<br><br>[accesses]" //CHECK THIS

		else
			body = "<a href='?src=[REF(src)];choice=auth'>{Log in}</a> <br><hr>"
			body += "<a href='?src=[REF(src)];choice=mode;mode_target=1'>Access Crew Manifest</a>"
			if(!target_dept)
				body += "<br><hr><a href = '?src=[REF(src)];choice=mode;mode_target=2'>Job Management</a>"
			body += "<a href='?src=[REF(src)];choice=mode;mode_target=3'>Paycheck Management</a>"

		dat = "<tt>[header][body]<hr><br></tt>"
	var/datum/browser/popup = new(user, "id_com", src.name, 900, 620)
	popup.set_content(dat)
	popup.open()

/obj/machinery/computer/card/Topic(href, href_list)
	if(..())
		return

	if(!usr.canUseTopic(src, !issilicon(usr)) || !is_operational())
		usr.unset_machine()
		usr << browse(null, "window=id_com")
		return

	usr.set_machine(src)
	switch(href_list["choice"])
		if ("modify")
			eject_id_modify(usr)
		if ("scan")
			eject_id_scan(usr)
		if ("auth")
			if ((!( authenticated ) && (scan || issilicon(usr)) && (modify || mode)))
				if (check_access(scan))
					region_access = list()
					head_subordinates = list()
					if(ACCESS_CHANGE_IDS in scan.access)
						if(target_dept)
							head_subordinates = get_all_jobs()
							region_access |= target_dept
							authenticated = 1
						else
							authenticated = 2
						playsound(src, 'sound/machines/terminal_on.ogg', 50, 0)

					else
						if((ACCESS_HOP in scan.access) && ((target_dept==DEPT_GEN) || !target_dept))
							region_access |= DEPT_GEN
							region_access |= DEPT_SUP //Currently no seperation between service/civillian and supply
							get_subordinates("Head of Personnel")
						if((ACCESS_HOS in scan.access) && ((target_dept==DEPT_SEC) || !target_dept))
							region_access |= DEPT_SEC
							get_subordinates("Head of Security")
						if((ACCESS_CMO in scan.access) && ((target_dept==DEPT_MED) || !target_dept))
							region_access |= DEPT_MED
							get_subordinates("Chief Medical Officer")
						if((ACCESS_RD in scan.access) && ((target_dept==DEPT_SCI) || !target_dept))
							region_access |= DEPT_SCI
							get_subordinates("Research Director")
						if((ACCESS_CE in scan.access) && ((target_dept==DEPT_ENG) || !target_dept))
							region_access |= DEPT_ENG
							get_subordinates("Chief Engineer")
						if(region_access)
							authenticated = 1
			else if ((!( authenticated ) && issilicon(usr)) && (!modify))
				to_chat(usr, "<span class='warning'>You can't modify an ID without an ID inserted to modify! Once one is in the modify slot on the computer, you can log in.</span>")
		if ("logout")
			region_access = null
			head_subordinates = null
			authenticated = 0
			playsound(src, 'sound/machines/terminal_off.ogg', 50, 0)

		if("access")
			if(href_list["allowed"])
				if(authenticated)
					var/access_type = text2num(href_list["access_target"])
					var/access_allowed = text2num(href_list["allowed"])
					if(access_type in (istype(src, /obj/machinery/computer/card/centcom)?get_all_centcom_access() : get_all_accesses()))
						modify.access -= access_type
						log_id("[key_name(usr)] removed [get_access_desc(access_type)] from [modify] using [scan] at [AREACOORD(usr)].")
						if(access_allowed == 1)
							modify.access += access_type
							log_id("[key_name(usr)] added [get_access_desc(access_type)] to [modify] using [scan] at [AREACOORD(usr)].")
						playsound(src, "terminal_type", 50, 0)
		if ("assign")
			if (authenticated == 2)
				var/t1 = href_list["assign_target"]
				if(t1 == "Custom")
					var/newJob = reject_bad_text(input("Enter a custom job assignment.", "Assignment", modify ? modify.assignment : "Unassigned"), MAX_NAME_LEN)
					if(newJob)
						t1 = newJob
						log_id("[key_name(usr)] changed [modify] assignment to [newJob] using [scan] at [AREACOORD(usr)].")

				else if(t1 == "Unassigned")
					modify.access -= get_all_accesses()
					log_id("[key_name(usr)] unassigned and stripped all access from [modify] using [scan] at [AREACOORD(usr)].")

				else
					var/datum/job/jobdatum
					for(var/jobtype in typesof(/datum/job))
						var/datum/job/J = new jobtype
						if(ckey(J.title) == ckey(t1))
							jobdatum = J
							updateUsrDialog()
							break

					if(!jobdatum)
						to_chat(usr, "<span class='error'>No log exists for this job.</span>")
						updateUsrDialog()
						return

					if(modify.registered_account)
						modify.registered_account.account_job = jobdatum // this is a terrible idea and people will grief but sure whatever

					modify.access = ( istype(src, /obj/machinery/computer/card/centcom) ? get_centcom_access(t1) : jobdatum.get_access() )
					log_id("[key_name(usr)] assigned [jobdatum] job to [modify], overriding all previous access using [scan] at [AREACOORD(usr)].")

				if (modify)
					modify.assignment = t1
					playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, 0)
		if ("demote")
			if(modify.assignment in head_subordinates || modify.assignment == "Assistant")
				modify.assignment = "Unassigned"
				log_id("[key_name(usr)] demoted [modify], unassigning the card without affecting access, using [scan] at [AREACOORD(usr)].")
				playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, 0)
			else
				to_chat(usr, "<span class='error'>You are not authorized to demote this position.</span>")
		if ("reg")
			if (authenticated)
				var/t2 = modify
				if ((authenticated && modify == t2 && (in_range(src, usr) || issilicon(usr)) && isturf(loc)))
					var/newName = reject_bad_name(href_list["reg"])
					if(newName)
						log_id("[key_name(usr)] changed [modify] name to '[newName]', using [scan] at [AREACOORD(usr)].")
						modify.registered_name = newName
						playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, 0)
					else
						to_chat(usr, "<span class='error'>Invalid name entered.</span>")
						updateUsrDialog()
						return
		if ("mode")
			mode = text2num(href_list["mode_target"])

		if("return")
			//DISPLAY MAIN MENU
			mode = 0
			playsound(src, "terminal_type", 25, 0)

		if("make_job_available")
			// MAKE ANOTHER JOB POSITION AVAILABLE FOR LATE JOINERS
			if(scan && (ACCESS_CHANGE_IDS in scan.access) && !target_dept)
				var/edit_job_target = href_list["job"]
				var/datum/job/j = SSjob.GetJob(edit_job_target)
				if(!j)
					updateUsrDialog()
					return 0
				if(can_open_job(j) != 1)
					updateUsrDialog()
					return 0
				if(opened_positions[edit_job_target] >= 0)
					GLOB.time_last_changed_position = world.time / 10
				j.total_positions++
				opened_positions[edit_job_target]++
				playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, 0)

		if("make_job_unavailable")
			// MAKE JOB POSITION UNAVAILABLE FOR LATE JOINERS
			if(scan && (ACCESS_CHANGE_IDS in scan.access) && !target_dept)
				var/edit_job_target = href_list["job"]
				var/datum/job/j = SSjob.GetJob(edit_job_target)
				if(!j)
					updateUsrDialog()
					return 0
				if(can_close_job(j) != 1)
					updateUsrDialog()
					return 0
				//Allow instant closing without cooldown if a position has been opened before
				if(opened_positions[edit_job_target] <= 0)
					GLOB.time_last_changed_position = world.time / 10
				j.total_positions--
				opened_positions[edit_job_target]--
				playsound(src, 'sound/machines/terminal_prompt_deny.ogg', 50, 0)

		if ("prioritize_job")
			// TOGGLE WHETHER JOB APPEARS AS PRIORITIZED IN THE LOBBY
			if(scan && (ACCESS_CHANGE_IDS in scan.access) && !target_dept)
				var/priority_target = href_list["job"]
				var/datum/job/j = SSjob.GetJob(priority_target)
				if(!j)
					updateUsrDialog()
					return 0
				var/priority = TRUE
				if(j in SSjob.prioritized_jobs)
					SSjob.prioritized_jobs -= j
					priority = FALSE
				else if(j.total_positions <= j.current_positions)
					to_chat(usr, "<span class='notice'>[j.title] has had all positions filled. Open up more slots before prioritizing it.</span>")
					updateUsrDialog()
					return
				else
					SSjob.prioritized_jobs += j
				to_chat(usr, "<span class='notice'>[j.title] has been successfully [priority ?  "prioritized" : "unprioritized"]. Potential employees will notice your request.</span>")
				playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, 0)

		if ("adjust_pay")
			//Adjust the paycheck of a crew member. Can't be less than zero.
			if(!scan)
				updateUsrDialog()
				return
			var/account_name = href_list["account"]
			var/datum/bank_account/account = null
			for(var/datum/bank_account/B in SSeconomy.bank_accounts)
				if(B.account_holder == account_name)
					account = B
					break
			if(isnull(account))
				updateUsrDialog()
				return
			switch(account.account_job.paycheck_department) //Checking if the user has access to change pay.
				if(ACCOUNT_SRV,ACCOUNT_CIV,ACCOUNT_CAR)
					if(!(ACCESS_HOP in scan.access))
						updateUsrDialog()
						return
				if(ACCOUNT_SEC)
					if(!(ACCESS_HOS in scan.access))
						updateUsrDialog()
						return
				if(ACCOUNT_MED)
					if(!(ACCESS_CMO in scan.access))
						updateUsrDialog()
						return
				if(ACCOUNT_SCI)
					if(!(ACCESS_RD in scan.access))
						updateUsrDialog()
						return
				if(ACCOUNT_ENG)
					if(!(ACCESS_CE in scan.access))
						updateUsrDialog()
						return
			var/new_pay = FLOOR(input(usr, "Input the new paycheck amount.", "Set new paycheck amount.", account.paycheck_amount) as num|null, 1)
			if(isnull(new_pay))
				updateUsrDialog()
				return
			if(new_pay < 0)
				to_chat(usr, "<span class='warning'>Paychecks cannot be negative.</span>")
				updateUsrDialog()
				return
			account.paycheck_amount = new_pay

		if ("adjust_bonus")
			//Adjust the bonus pay of a crew member. Negative amounts dock pay.
			if(!scan)
				updateUsrDialog()
				return
			var/account_name = href_list["account"]
			var/datum/bank_account/account = null
			for(var/datum/bank_account/B in SSeconomy.bank_accounts)
				if(B.account_holder == account_name)
					account = B
					break
			if(isnull(account))
				updateUsrDialog()
				return
			switch(account.account_job.paycheck_department) //Checking if the user has access to change pay.
				if(ACCOUNT_SRV,ACCOUNT_CIV,ACCOUNT_CAR)
					if(!(ACCESS_HOP in scan.access))
						updateUsrDialog()
						return
				if(ACCOUNT_SEC)
					if(!(ACCESS_HOS in scan.access))
						updateUsrDialog()
						return
				if(ACCOUNT_MED)
					if(!(ACCESS_CMO in scan.access))
						updateUsrDialog()
						return
				if(ACCOUNT_SCI)
					if(!(ACCESS_RD in scan.access))
						updateUsrDialog()
						return
				if(ACCOUNT_ENG)
					if(!(ACCESS_CE in scan.access))
						updateUsrDialog()
						return
			var/new_bonus = FLOOR(input(usr, "Input the bonus amount. Negative values will dock paychecks.", "Set paycheck bonus", account.paycheck_bonus) as num|null, 1)
			if(isnull(new_bonus))
				updateUsrDialog()
				return
			account.paycheck_bonus = new_bonus

		if ("print")
			if (!( printing ))
				printing = 1
				sleep(50)
				var/obj/item/paper/P = new /obj/item/paper( loc )
				var/t1 = "<B>Crew Manifest:</B><BR>"
				for(var/datum/data/record/t in sortRecord(GLOB.data_core.general))
					t1 += t.fields["name"] + " - " + t.fields["rank"] + "<br>"
				P.info = t1
				P.name = "paper- 'Crew Manifest'"
				printing = null
				playsound(src, 'sound/machines/terminal_insert_disc.ogg', 50, 0)
	if (modify)
		modify.update_label()
	updateUsrDialog()

/obj/machinery/computer/card/AltClick(mob/user)
	if(!user.canUseTopic(src, !issilicon(user)) || !is_operational())
		return
	if(scan)
		eject_id_scan(user)
	if(modify)
		eject_id_modify(user)

/obj/machinery/computer/card/proc/eject_id_scan(mob/user)
	if(scan)
		scan.forceMove(drop_location())
		if(!issilicon(user) && Adjacent(user))
			user.put_in_hands(scan)
		playsound(src, 'sound/machines/terminal_insert_disc.ogg', 50, 0)
		scan = null
	else //switching the ID with the one you're holding
		if(issilicon(user) || !Adjacent(user))
			return
		var/obj/item/I = user.get_active_held_item()
		if(istype(I, /obj/item/card/id))
			if(!user.transferItemToLoc(I,src))
				return
			playsound(src, 'sound/machines/terminal_insert_disc.ogg', 50, 0)
			scan = I
	authenticated = FALSE
	updateUsrDialog()

/obj/machinery/computer/card/proc/eject_id_modify(mob/user)
	if(modify)
		GLOB.data_core.manifest_modify(modify.registered_name, modify.assignment)
		modify.update_label()
		modify.forceMove(drop_location())
		if(!issilicon(user) && Adjacent(user))
			user.put_in_hands(modify)
		playsound(src, 'sound/machines/terminal_insert_disc.ogg', 50, 0)
		modify = null
		region_access = null
		head_subordinates = null
	else //switching the ID with the one you're holding
		if(issilicon(user) || !Adjacent(user))
			return
		var/obj/item/I = user.get_active_held_item()
		if(istype(I, /obj/item/card/id))
			if (!user.transferItemToLoc(I,src))
				return
			playsound(src, 'sound/machines/terminal_insert_disc.ogg', 50, 0)
			modify = I
	authenticated = FALSE
	updateUsrDialog()

/obj/machinery/computer/card/proc/get_subordinates(rank)
	for(var/datum/job/job in SSjob.occupations)
		if(rank in job.department_head)
			head_subordinates += job.title

/obj/machinery/computer/card/centcom
	name = "\improper CentCom identification console"
	circuit = /obj/item/circuitboard/computer/card/centcom
	req_access = list(ACCESS_CENT_CAPTAIN)

/obj/machinery/computer/card/minor
	name = "department management console"
	desc = "You can use this to change ID's for specific departments."
	icon_screen = "idminor"
	circuit = /obj/item/circuitboard/computer/card/minor

/obj/machinery/computer/card/minor/Initialize(mapload)
	. = ..()
	var/obj/item/circuitboard/computer/card/minor/typed_circuit = circuit
	if(target_dept)
		typed_circuit.target_dept = target_dept
	else
		target_dept = typed_circuit.target_dept
	var/list/dept_list = list("general","security","medical","science","engineering")
	name = "[dept_list[target_dept]] department console"

/obj/machinery/computer/card/minor/hos
	target_dept = DEPT_SEC
	icon_screen = "idhos"

	light_color = LIGHT_COLOR_RED

/obj/machinery/computer/card/minor/cmo
	target_dept = DEPT_MED
	icon_screen = "idcmo"

/obj/machinery/computer/card/minor/rd
	target_dept = DEPT_SCI
	icon_screen = "idrd"

	light_color = LIGHT_COLOR_PINK

/obj/machinery/computer/card/minor/ce
	target_dept = DEPT_ENG
	icon_screen = "idce"

	light_color = LIGHT_COLOR_YELLOW

#undef DEPT_ALL
#undef DEPT_GEN
#undef DEPT_SEC
#undef DEPT_MED
#undef DEPT_SCI
#undef DEPT_ENG
#undef DEPT_SUP
