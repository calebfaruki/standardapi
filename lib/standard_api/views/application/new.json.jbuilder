json.partial! model_partial(model), model_partial(model).split('/').last.to_sym => instance_variable_get("@#{model.model_name.singular}"), includes: includes
