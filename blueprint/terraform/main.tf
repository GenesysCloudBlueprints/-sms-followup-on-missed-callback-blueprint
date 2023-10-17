terraform {
  required_providers {
    genesyscloud = {
     source = "mypurecloud/genesyscloud"
     version= "1.23.0"
    }
  }
}

data "genesyscloud_user" "callback_agent" {
  email = var.callback_agent_email
}

module "callback_sms_integration" {
    source = "git::https://github.com/GenesysCloudDevOps/public-api-data-actions-integration-module.git?ref=main"

    integration_name                = "Callback SMS Integrations"
    integration_creds_client_id     = var.callback_sms_oauthclient
    integration_creds_client_secret = var.callback_sms_oauthsecret
}

module "callback_sms_dataaction" {
    source             = "git::https://github.com/GenesysCloudDevOps/public-api-send-sms-data-action-module.git?ref=main"
    action_name        = "Send SMS"
    action_category    = "${module.callback_sms_integration.integration_name}"
    integration_id     = "${module.callback_sms_integration.integration_id}"
    secure_data_action = false
}

resource "genesyscloud_routing_wrapupcode" "cust_unavailable" {
  name = "Cust unavailable"
}


resource "genesyscloud_routing_queue" "sms_callback_queue" {
  name                     = "smsa"
  description              = "SMS Callback Queues"
  acw_wrapup_prompt        = "MANDATORY_TIMEOUT"
  acw_timeout_ms           = 300000
  skill_evaluation_method  = "BEST"
  auto_answer_only         = true
  enable_transcription     = true
  enable_manual_assignment = true
  wrapup_codes             = [genesyscloud_routing_wrapupcode.cust_unavailable.id]
  members {
    user_id = data.genesyscloud_user.callback_agent.id
    ring_num=1
  }
}

resource "genesyscloud_flow" "sms_eventrigger_flow" {
  depends_on = [
    module.callback_sms_dataaction
  ]  
  filepath = "${path.module}/architect/callback_sms_eventrigger_flow.yaml.tftpl"
  file_content_hash = filesha256("${path.module}/architect/callback_sms_eventrigger_flow.yaml.tftpl")
  substitutions = {
    callback_originating_sms_phonenumber            = var.callback_originating_sms_phonenumber
    callback_phonenumber                            = var.callback_phonenumber
    callback_division                               = var.callback_division
  }
}

resource "genesyscloud_processautomation_trigger" "trigger" {
  name       = "MyUnansweredCallbackTrigger"
  topic_name = "v2.detail.events.conversation.{id}.acw"
  enabled    = true

  target {
    id   = genesyscloud_flow.sms_eventrigger_flow.id
    type = "Workflow"
  }
  
  match_criteria = jsonencode([
        {
            "jsonPath": "queueId",
            "operator": "Equal",
            "value": genesyscloud_routing_queue.sms_callback_queue.id
        },
        {
            "jsonPath": "wrapupCode",
            "operator":  "Equal",
            "value":  genesyscloud_routing_wrapupcode.cust_unavailable.id
        },
        {
            "jsonPath": "mediaType",
            "operator":  "Equal",
            "value": "CALLBACK"
        }
    ])

  event_ttl_seconds = 60
} 



